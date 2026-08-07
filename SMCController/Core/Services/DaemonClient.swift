//
//  DaemonClient.swift
//  SMCController
//
//  Secure XPC transport for the root helper.
//

import Foundation
import Security
import XPC

enum HelperAvailability: Equatable, Sendable {
    case ready
    case notInstalled
    case updateRequired
    case failed(String)

    var isReady: Bool {
        self == .ready
    }

    var statusMessage: String {
        switch self {
        case .ready:
            return L10n.string("privileges.helper.installed.running")
        case .notInstalled:
            return L10n.string("privileges.helper.notInstalled")
        case .updateRequired:
            return "The installed helper must be updated to support secure XPC communication."
        case .failed(let message):
            return message
        }
    }
}

enum HelperRequestValue: Equatable, Sendable {
    case int64(Int64)
    case bool(Bool)
    case string(String)
}

enum HelperErrorCode: String, Sendable {
    case invalidRequest
    case outOfRange
    case hardwareUnavailable
    case smcFailure
    case incompatibleVersion
}

/// Protocol-v2 requests are kept as Swift values until they cross the XPC boundary.
/// This makes the exact wire representation independently testable.
struct HelperRequest: Equatable, Sendable {
    nonisolated static let protocolVersion: Int64 = 2

    let fields: [String: HelperRequestValue]

    static let check = HelperRequest(operation: "check")
    static let power = HelperRequest(operation: "power")

    static func setFan(fan: Int, rpm: Int) -> HelperRequest {
        HelperRequest(operation: "setFan", fields: [
            "fan": .int64(Int64(fan)),
            "rpm": .int64(Int64(rpm))
        ])
    }

    static func setMode(enabled: Bool, watchdogSeconds: Int? = nil) -> HelperRequest {
        var fields: [String: HelperRequestValue] = ["enabled": .bool(enabled)]
        if enabled, let watchdogSeconds {
            fields["watchdogSeconds"] = .int64(Int64(watchdogSeconds))
        }
        return HelperRequest(operation: "setMode", fields: fields)
    }

    static func readKey(_ key: String) -> HelperRequest {
        HelperRequest(operation: "readKey", fields: ["key": .string(key)])
    }

    init(operation: String, fields: [String: HelperRequestValue] = [:]) {
        var requestFields = fields
        requestFields["protocolVersion"] = .int64(Self.protocolVersion)
        requestFields["operation"] = .string(operation)
        self.fields = requestFields
    }
}

enum DaemonClientError: LocalizedError, Sendable {
    case timeout
    case connection(String)
    case malformedReply(String)
    case incompatibleProtocol(Int64)
    case helper(HelperErrorCode, String)
    case signingRequirement(String)
    case installation(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "The helper did not reply within 2 seconds."
        case .connection(let message), .malformedReply(let message), .helper(_, let message),
             .signingRequirement(let message), .installation(let message):
            return message
        case .incompatibleProtocol(let version):
            return "The installed helper uses unsupported protocol version \(version)."
        }
    }

    var shouldReconnect: Bool {
        switch self {
        case .timeout, .connection:
            return true
        case .malformedReply, .incompatibleProtocol, .helper, .signingRequirement, .installation:
            return false
        }
    }
}

actor DaemonClient {
    static let shared = DaemonClient()

    static let serviceName = "com.minepacu.SMCHelper"
    static let helperPath = "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
    static let helperPlistPath = "/Library/LaunchDaemons/com.minepacu.SMCHelper.plist"

    struct PowerMetrics: Sendable, Equatable {
        let cpu: Double?
        let gpu: Double?
        let dc: Double?
    }

    struct SMCKeyValue: Sendable, Equatable {
        let key: String
        let data: Data
        let dataSize: Int
        let dataType: UInt32
    }

    private final class Connection: @unchecked Sendable {
        let raw: xpc_connection_t

        init(_ raw: xpc_connection_t) {
            self.raw = raw
        }

        deinit {
            xpc_connection_cancel(raw)
        }
    }

    /// An XPC reply can arrive after the request task has timed out. This gate makes
    /// cancellation and the eventual callback race-safe so a continuation is resumed once.
    private final class ReplyGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Reply, Error>?
        private var pendingResult: Result<Reply, Error>?

        func install(_ continuation: CheckedContinuation<Reply, Error>) {
            lock.lock()
            if let pendingResult {
                lock.unlock()
                continuation.resume(with: pendingResult)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func complete(_ result: Result<Reply, Error>) {
            lock.lock()
            guard pendingResult == nil else {
                lock.unlock()
                return
            }
            pendingResult = result
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }
    }

    private struct Reply: Sendable {
        let fields: [String: HelperReplyValue]

        var isOK: Bool {
            if case .bool(true)? = fields["ok"] {
                return true
            }
            return false
        }

        var errorMessage: String? {
            if case .string(let value)? = fields["message"] {
                return value
            }
            return nil
        }

        var errorCode: HelperErrorCode? {
            guard case .string(let value)? = fields["errorCode"] else { return nil }
            return HelperErrorCode(rawValue: value)
        }

        var protocolVersion: Int64? {
            if case .int64(let value)? = fields["protocolVersion"] {
                return value
            }
            return nil
        }
    }

    private enum HelperReplyValue: Sendable {
        case int64(Int64)
        case bool(Bool)
        case double(Double)
        case string(String)
        case data(Data)
    }

    private var connection: Connection?
    private var powerStreamTask: Task<Void, Never>?

    private init() {}

    nonisolated var isHelperInstalled: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: Self.helperPath)
            && fileManager.isExecutableFile(atPath: Self.helperPath)
    }

    /// Checks the installed helper without requesting authorization or starting a legacy daemon.
    func helperAvailability() async -> HelperAvailability {
        guard isHelperInstalled else { return .notInstalled }

        do {
            let reply = try await request(HelperRequest.check)
            guard let version = reply.protocolVersion else {
                return .updateRequired
            }
            guard version == HelperRequest.protocolVersion else {
                return .updateRequired
            }
            guard reply.isOK else {
                if reply.errorCode == .incompatibleVersion {
                    return .updateRequired
                }
                return .failed(reply.errorMessage ?? "The helper rejected the status check.")
            }
            guard case .string(let helperVersion)? = reply.fields["helperVersion"],
                  helperVersion.split(separator: ".").first == "2" else {
                return .updateRequired
            }
            return .ready
        } catch let error as DaemonClientError {
            switch error {
            case .incompatibleProtocol, .malformedReply, .timeout, .connection:
                // A pre-v2 helper has no XPC endpoint, so it fails exactly this way.
                return .updateRequired
            case .helper(.incompatibleVersion, _):
                return .updateRequired
            case .helper(_, let message), .signingRequirement(let message), .installation(let message):
                return .failed(message)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var isAvailableWithoutPrompt: Bool {
        get async {
            await helperAvailability().isReady
        }
    }

    /// Retained for existing callers. It deliberately never triggers an authorization prompt.
    func startDaemon() async -> Bool {
        await helperAvailability().isReady
    }

    func checkDaemon() async -> Bool {
        await helperAvailability().isReady
    }

    /// Explicit installation entry point; callers should invoke this only from a user action.
    func installHelperFromBundle() async -> Bool {
        do {
            let resources = try bundledInstallationResources()
            try executeInstallerWithAuthorization(
                installerPath: resources.installer.path,
                helperBinary: resources.helper.path,
                plistFile: resources.plist.path,
                appBundlePath: Bundle.main.bundleURL.path
            )

            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if await helperAvailability().isReady {
                    return true
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            return false
        } catch {
            print("[DaemonClient] Helper installation failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetches helper-cached power metrics without elevating privileges.
    func fetchPowerMetrics() async -> PowerMetrics? {
        await fetchPowerMetricsIfAvailable()
    }

    /// Fetches power only after a non-interactive XPC health check succeeds.
    func fetchPowerMetricsIfAvailable() async -> PowerMetrics? {
        guard await helperAvailability().isReady else { return nil }

        do {
            let reply = try await request(.power)
            return try powerMetrics(from: reply)
        } catch {
            return nil
        }
    }

    /// Uses short polling rather than a persistent stream so cancellation is immediate and bounded.
    func startPowerStream(
        onUpdate: @escaping @MainActor (PowerMetrics) -> Void,
        onError: @escaping @MainActor () -> Void = {}
    ) {
        stopPowerStream()
        powerStreamTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                if let metrics = await self.fetchPowerMetricsIfAvailable() {
                    await onUpdate(metrics)
                } else if !Task.isCancelled {
                    await onError()
                }

                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stopPowerStream() {
        powerStreamTask?.cancel()
        powerStreamTask = nil
    }

    func setFanSpeed(fan: Int, rpm: Int) async throws {
        let reply = try await request(.setFan(fan: fan, rpm: rpm))
        try ensureSuccessful(reply)
    }

    func setManualMode(enabled: Bool, watchdogSeconds: Int? = nil) async throws {
        if enabled {
            guard let watchdogSeconds else {
                throw DaemonClientError.helper(
                    .invalidRequest,
                    "A watchdog lease is required when enabling manual fan control."
                )
            }
            guard (15...60).contains(watchdogSeconds) else {
                throw DaemonClientError.helper(
                    .outOfRange,
                    "The watchdog lease must be between 15 and 60 seconds."
                )
            }
        }

        let reply = try await request(.setMode(enabled: enabled, watchdogSeconds: watchdogSeconds))
        try ensureSuccessful(reply)
    }

    func readKey(_ key: String) async throws -> SMCKeyValue {
        let reply = try await request(.readKey(key))
        try ensureSuccessful(reply)
        guard case .string(let returnedKey)? = reply.fields["key"],
              case .data(let data)? = reply.fields["data"],
              case .int64(let dataSize)? = reply.fields["dataSize"],
              case .int64(let dataType)? = reply.fields["dataType"],
              dataSize >= 0,
              dataType >= 0,
              data.count >= Int(dataSize) else {
            throw DaemonClientError.malformedReply("The helper returned malformed data for \(key).")
        }
        return SMCKeyValue(
            key: returnedKey,
            data: data,
            dataSize: Int(dataSize),
            dataType: UInt32(truncatingIfNeeded: dataType)
        )
    }

    private func request(_ request: HelperRequest) async throws -> Reply {
        do {
            return try await requestOnce(request)
        } catch let error as DaemonClientError where error.shouldReconnect {
            invalidateConnection()
            return try await requestOnce(request)
        }
    }

    private func requestOnce(_ request: HelperRequest) async throws -> Reply {
        let connection = try makeConnectionIfNeeded()

        return try await withThrowingTaskGroup(of: Reply.self) { group in
            group.addTask {
                try await Self.send(request, over: connection)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                throw DaemonClientError.timeout
            }

            guard let first = try await group.next() else {
                throw DaemonClientError.connection("The XPC request ended without a reply.")
            }
            group.cancelAll()
            return first
        }
    }

    private func makeConnectionIfNeeded() throws -> Connection {
        if let connection {
            return connection
        }

        let requirement = try bundledHelperDesignatedRequirement()
        let rawConnection = Self.serviceName.withCString {
            xpc_connection_create_mach_service($0, nil, UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED))
        }
        let newConnection = Connection(rawConnection)

        let requirementStatus = requirement.withCString {
            xpc_connection_set_peer_code_signing_requirement(rawConnection, $0)
        }
        guard requirementStatus == 0 else {
            throw DaemonClientError.signingRequirement(
                "Could not apply the bundled helper signing requirement (\(requirementStatus))."
            )
        }

        xpc_connection_set_event_handler(rawConnection) { _ in
            // Per-request reply handlers receive connection errors. Keeping this handler empty
            // avoids treating a normal launchd interruption as a persistent helper failure.
        }
        xpc_connection_activate(rawConnection)
        connection = newConnection
        return newConnection
    }

    private func invalidateConnection() {
        connection = nil
    }

    private static func send(_ request: HelperRequest, over connection: Connection) async throws -> Reply {
        let gate = ReplyGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                guard !Task.isCancelled else {
                    gate.complete(.failure(CancellationError()))
                    return
                }

                let message = xpc_dictionary_create(nil, nil, 0)
                for (key, value) in request.fields {
                    switch value {
                    case .int64(let integer):
                        xpc_dictionary_set_int64(message, key, integer)
                    case .bool(let bool):
                        xpc_dictionary_set_bool(message, key, bool)
                    case .string(let string):
                        string.withCString { xpc_dictionary_set_string(message, key, $0) }
                    }
                }

                xpc_connection_send_message_with_reply(connection.raw, message, .global()) { response in
                    gate.complete(Result {
                        try reply(from: response)
                    })
                }
            }
        } onCancel: {
            gate.complete(.failure(CancellationError()))
        }
    }

    private static func reply(from response: xpc_object_t) throws -> Reply {
        if xpc_get_type(response) == XPC_TYPE_ERROR {
            let description = xpc_dictionary_get_string(response, XPC_ERROR_KEY_DESCRIPTION)
                .map { String(cString: $0) } ?? "Unknown XPC connection error."
            throw DaemonClientError.connection(description)
        }

        guard xpc_get_type(response) == XPC_TYPE_DICTIONARY else {
            throw DaemonClientError.malformedReply("The helper returned a non-dictionary XPC response.")
        }

        guard let protocolValue = xpc_dictionary_get_value(response, "protocolVersion"),
              xpc_get_type(protocolValue) == XPC_TYPE_INT64 else {
            throw DaemonClientError.malformedReply("The helper reply omitted its protocol version.")
        }
        let protocolVersion = xpc_int64_get_value(protocolValue)
        guard protocolVersion == HelperRequest.protocolVersion else {
            throw DaemonClientError.incompatibleProtocol(protocolVersion)
        }

        guard let okValue = xpc_dictionary_get_value(response, "ok"),
              xpc_get_type(okValue) == XPC_TYPE_BOOL else {
            throw DaemonClientError.malformedReply("The helper reply omitted its success status.")
        }

        var fields: [String: HelperReplyValue] = [
            "protocolVersion": .int64(protocolVersion),
            "ok": .bool(xpc_bool_get_value(okValue))
        ]
        for key in ["errorCode", "message", "helperVersion", "key"] {
            if let value = xpc_dictionary_get_string(response, key) {
                fields[key] = .string(String(cString: value))
            }
        }
        for key in ["cpu", "gpu", "dc", "timestamp"] {
            if let value = xpc_dictionary_get_value(response, key) {
                if xpc_get_type(value) == XPC_TYPE_DOUBLE {
                    fields[key] = .double(xpc_double_get_value(value))
                } else if xpc_get_type(value) == XPC_TYPE_INT64 {
                    fields[key] = .double(Double(xpc_int64_get_value(value)))
                }
            }
        }
        for key in ["dataSize", "dataType"] {
            if let value = xpc_dictionary_get_value(response, key),
               xpc_get_type(value) == XPC_TYPE_INT64 {
                fields[key] = .int64(xpc_int64_get_value(value))
            }
        }
        var dataLength = 0
        if let dataPointer = xpc_dictionary_get_data(response, "data", &dataLength) {
            fields["data"] = .data(Data(bytes: dataPointer, count: dataLength))
        }

        return Reply(fields: fields)
    }

    private func ensureSuccessful(_ reply: Reply) throws {
        guard reply.isOK else {
            guard let errorCode = reply.errorCode else {
                throw DaemonClientError.malformedReply("The helper rejected the request without an error code.")
            }
            throw DaemonClientError.helper(errorCode, reply.errorMessage ?? "The helper rejected the request.")
        }
    }

    private func powerMetrics(from reply: Reply) throws -> PowerMetrics {
        try ensureSuccessful(reply)

        func value(named key: String) -> Double? {
            if case .double(let value)? = reply.fields[key] {
                return value
            }
            return nil
        }

        return PowerMetrics(cpu: value(named: "cpu"), gpu: value(named: "gpu"), dc: value(named: "dc"))
    }

    private func bundledInstallationResources() throws -> (helper: URL, plist: URL, installer: URL) {
        let bundle = Bundle.main
        let helper = bundle.url(forResource: "SMCControllerHelper", withExtension: nil, subdirectory: "SMCHelper")
        let plist = bundle.url(forResource: "com.minepacu.SMCHelper", withExtension: "plist", subdirectory: "SMCHelper")
        let installer = bundle.url(forResource: "install_helper", withExtension: nil, subdirectory: "SMCHelper")

        guard let helper, let plist, let installer else {
            throw DaemonClientError.installation("The signed helper installer resources are missing from this app bundle.")
        }
        return (helper, plist, installer)
    }

    private func bundledHelperDesignatedRequirement() throws -> String {
        let helperURL = try bundledInstallationResources().helper
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(helperURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw DaemonClientError.signingRequirement("Could not read the bundled helper signature.")
        }
        guard SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else {
            throw DaemonClientError.signingRequirement("The bundled helper signature is not valid.")
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let signingInformation,
        let requirementObject = (signingInformation as NSDictionary)[kSecCodeInfoDesignatedRequirement] else {
            throw DaemonClientError.signingRequirement("The bundled helper has no designated signing requirement.")
        }
        // Security.framework guarantees this value is a SecRequirement for the designated key.
        let requirement = requirementObject as! SecRequirement

        var requirementString: CFString?
        guard SecRequirementCopyString(requirement, [], &requirementString) == errSecSuccess,
              let requirementString else {
            throw DaemonClientError.signingRequirement("Could not convert the helper signing requirement.")
        }
        return requirementString as String
    }

    private func executeInstallerWithAuthorization(
        installerPath: String,
        helperBinary: String,
        plistFile: String,
        appBundlePath: String
    ) throws {
        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess,
              let authorization else {
            throw DaemonClientError.installation("Could not create an authorization session.")
        }
        defer { AuthorizationFree(authorization, []) }

        let rightName = kAuthorizationRightExecute
        let authorizationStatus = rightName.withCString { rightNamePointer in
            var item = AuthorizationItem(name: rightNamePointer, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil
                )
            }
        }
        guard authorizationStatus == errAuthorizationSuccess else {
            throw DaemonClientError.installation("Administrator authorization was denied.")
        }

        var outputFile: UnsafeMutablePointer<FILE>?
        let executionStatus = installerPath.withCString { installerPointer in
            let helperArgument = strdup(helperBinary)
            let plistArgument = strdup(plistFile)
            let bundleArgument = strdup(appBundlePath)
            var arguments: [UnsafeMutablePointer<CChar>?] = [helperArgument, plistArgument, bundleArgument, nil]
            defer {
                free(helperArgument)
                free(plistArgument)
                free(bundleArgument)
            }

            return arguments.withUnsafeMutableBufferPointer { argumentsPointer in
                guard let process = dlopen(nil, RTLD_NOW),
                      let symbol = dlsym(process, "AuthorizationExecuteWithPrivileges") else {
                    return OSStatus(-1)
                }
                typealias ExecuteWithPrivileges = @convention(c) (
                    AuthorizationRef,
                    UnsafePointer<CChar>,
                    AuthorizationFlags,
                    UnsafePointer<UnsafeMutablePointer<CChar>?>?,
                    UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
                ) -> OSStatus
                let execute = unsafeBitCast(symbol, to: ExecuteWithPrivileges.self)
                return execute(
                    authorization,
                    UnsafeMutablePointer(mutating: installerPointer),
                    [],
                    argumentsPointer.baseAddress,
                    &outputFile
                )
            }
        }
        guard executionStatus == errAuthorizationSuccess else {
            throw DaemonClientError.installation("The helper installer could not be started (\(executionStatus)).")
        }

        if let outputFile {
            defer { fclose(outputFile) }
            let output = FileHandle(fileDescriptor: fileno(outputFile)).readDataToEndOfFile()
            if let text = String(data: output, encoding: .utf8), !text.isEmpty {
                print("[DaemonClient] Installer: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }
}
