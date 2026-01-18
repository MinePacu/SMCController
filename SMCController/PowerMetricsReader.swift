//
//  PowerMetricsReader.swift
//  SMCController
//
//  Best-effort powermetrics sampling via Authorization Services.
//

import Foundation
import Security

struct PowerMetricsSample {
    let cpu: Double?
    let gpu: Double?
    let system: Double?
    let rawOutput: String
    let timestamp: Date
}

enum PowerMetricsError: Error {
    case authFailed(OSStatus)
    case execFailed(OSStatus)
    case noOutput
}

final class PowerMetricsReader {
    private static var cachedAuth: AuthorizationRef?
    private static var authDenied = false
    
    static var hasCachedAuthorization: Bool {
        cachedAuth != nil
    }
    
    /// Runs `powermetrics` once (requires privileges) and parses CPU/GPU/System power in watts.
    /// Set allowPrompt=false to avoid password prompts (will throw if not already authorized).
    static func sampleOnce(intervalMs: Int = 1200, allowPrompt: Bool = false) throws -> PowerMetricsSample {
        let shouldPrompt = allowPrompt && !authDenied
        let auth = try ensureAuthorization(allowPrompt: shouldPrompt)

        var outputFile: UnsafeMutablePointer<FILE>? = nil
        let command = "/usr/bin/powermetrics"
        let args = ["-n", "1", "-i", "\(intervalMs)", "--samplers", "cpu_power,gpu_power"]

        let execStatus = command.withCString { pathPtr in
            // Build C-string argv
            var cArgs = args.map { strdup($0) }
            cArgs.append(nil)
            defer { cArgs.forEach { if let ptr = $0 { free(ptr) } } }

            return cArgs.withUnsafeBufferPointer { buffer in
                guard let lib = dlopen(nil, RTLD_NOW),
                      let funcPtr = dlsym(lib, "AuthorizationExecuteWithPrivileges") else {
                    return OSStatus(-1)
                }

                typealias AuthExecFunc = @convention(c) (
                    AuthorizationRef,
                    UnsafePointer<CChar>,
                    AuthorizationFlags,
                    UnsafePointer<UnsafeMutablePointer<CChar>?>?,
                    UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
                ) -> OSStatus

                let function = unsafeBitCast(funcPtr, to: AuthExecFunc.self)
                return function(auth, pathPtr, [], buffer.baseAddress, &outputFile)
            }
        }

        guard execStatus == errAuthorizationSuccess else {
            throw PowerMetricsError.execFailed(execStatus)
        }

        var output = ""
        if let file = outputFile {
            let handle = FileHandle(fileDescriptor: fileno(file))
            if let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) {
                output = text
            }
            fclose(file)
        }

        guard !output.isEmpty else {
            throw PowerMetricsError.noOutput
        }

        let parsed = parse(output: output)
        return PowerMetricsSample(cpu: parsed.cpu,
                                  gpu: parsed.gpu,
                                  system: parsed.system,
                                  rawOutput: output,
                                  timestamp: Date())
    }
    
    private static func ensureAuthorization(allowPrompt: Bool) throws -> AuthorizationRef {
        if let cachedAuth {
            return cachedAuth
        }
        
        var authRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw PowerMetricsError.authFailed(status)
        }
        
        let flags: AuthorizationFlags = allowPrompt
            ? [.interactionAllowed, .extendRights, .preAuthorize]
            : [.extendRights]
        
        status = kAuthorizationRightExecute.withCString { namePtr in
            var authItem = AuthorizationItem(name: namePtr, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &authItem) { itemPtr in
                var authRights = AuthorizationRights(count: 1, items: itemPtr)
                return AuthorizationCopyRights(auth, &authRights, nil, flags, nil)
            }
        }
        
        guard status == errAuthorizationSuccess else {
            if !allowPrompt { authDenied = true }
            AuthorizationFree(auth, [])
            throw PowerMetricsError.authFailed(status)
        }
        
        cachedAuth = auth
        authDenied = false
        return auth
    }

    private static func parse(output: String) -> (cpu: Double?, gpu: Double?, system: Double?) {
        var cpu: Double?
        var gpu: Double?
        var system: Double?

        for line in output.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.localizedCaseInsensitiveContains("CPU Power") {
                cpu = firstNumber(in: String(l), line: l) ?? cpu
            } else if l.localizedCaseInsensitiveContains("GPU Power") {
                gpu = firstNumber(in: String(l), line: l) ?? gpu
            } else if l.localizedCaseInsensitiveContains("Combined System Power") ||
                        l.localizedCaseInsensitiveContains("System Total") ||
                        l.localizedCaseInsensitiveContains("Total Power") {
                system = firstNumber(in: String(l), line: l) ?? system
            }
        }

        return (cpu, gpu, system)
    }

    private static func firstNumber(in line: String, line fullLine: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            let value = Double(line[range])
            guard let v = value else { return nil }
            // powermetrics cpu_power/gpu_power often reports mW
            if fullLine.contains("mW") {
                return v / 1000.0
            }
            return v
        }
        return nil
    }
}
