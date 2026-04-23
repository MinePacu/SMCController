//
//  DaemonClient.swift
//  SMCController
//
//  Client for communicating with SMCHelper daemon via Unix socket
//

import Foundation
import Security

class DaemonClient {
    static let shared = DaemonClient()
    
    private let socketPath = "/tmp/com.minepacu.SMCHelper.socket"
    private let daemonPath = "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
    private let installFlagKey = "com.minepacu.smchelper.installed"
    
    private var isDaemonRunning = false
    private var installAttempted = false
    private var cachedAuth: AuthorizationRef?
    private var isHelperMarkedInstalled: Bool {
        UserDefaults.standard.bool(forKey: installFlagKey)
    }
    private var powerStreamTask: Task<Void, Never>?
    
    struct PowerMetrics: Sendable {
        let cpu: Double?
        let gpu: Double?
        let dc: Double?
    }
    
    private init() {
        // If helper files already exist (installed manually), remember to avoid re-prompting.
        if FileManager.default.fileExists(atPath: daemonPath) {
            UserDefaults.standard.set(true, forKey: installFlagKey)
        }
        checkDaemon()
    }
    
    /// Install daemon from bundled resources using prebuilt binaries
    private func installDaemonFromBundle() -> Bool {
        print("[DaemonClient] 🔧 Attempting to install daemon from bundle...")
        
        // Find bundled files (try both with and without SMCHelper directory)
        var helperBinary: String?
        var plistFile: String?
        var installerTool: String?
        
        // Try in SMCHelper subdirectory first
        helperBinary = Bundle.main.path(forResource: "SMCHelper", ofType: nil, inDirectory: "SMCHelper")
        plistFile = Bundle.main.path(forResource: "com.minepacu.SMCHelper", ofType: "plist", inDirectory: "SMCHelper")
        installerTool = Bundle.main.path(forResource: "install_helper", ofType: nil, inDirectory: "SMCHelper")
        
        // If not found, try in Resources root
        if helperBinary == nil {
            helperBinary = Bundle.main.path(forResource: "SMCHelper", ofType: nil)
        }
        if plistFile == nil {
            plistFile = Bundle.main.path(forResource: "com.minepacu.SMCHelper", ofType: "plist")
        }
        if installerTool == nil {
            installerTool = Bundle.main.path(forResource: "install_helper", ofType: nil)
        }
        
        guard let finalHelperBinary = helperBinary,
              let finalPlistFile = plistFile,
              let finalInstallerTool = installerTool else {
            print("[DaemonClient] ❌ Required files not found in bundle")
            print("[DaemonClient] Need: SMCHelper, com.minepacu.SMCHelper.plist, install_helper")
            
            // Debug: Print what we're looking for
            if let resourcePath = Bundle.main.resourcePath {
                print("[DaemonClient] Resource path: \(resourcePath)")
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("[DaemonClient] Resources contents: \(contents.filter { $0.contains("SMC") || $0.contains("install") })")
                } catch {
                    print("[DaemonClient] Could not list resources: \(error)")
                }
            }
            
            print("[DaemonClient] ℹ️ Run ./SMCHelper/prepare_bundle.sh and add files to Xcode")
            return false
        }
        
        print("[DaemonClient] ✅ Found helper binary: \(finalHelperBinary)")
        print("[DaemonClient] ✅ Found plist: \(finalPlistFile)")
        print("[DaemonClient] ✅ Found installer: \(finalInstallerTool)")
        
        // Use Authorization Services to run installer tool
        print("[DaemonClient] 🔐 Requesting admin privileges via Authorization Services...")
        print("[DaemonClient] 📢 YOU SHOULD SEE A PASSWORD PROMPT NOW")
        
        do {
            try executeInstallerWithAuth(installerPath: finalInstallerTool, 
                                         helperBinary: finalHelperBinary, 
                                         plistFile: finalPlistFile)
            
            // Wait for daemon to start
            print("[DaemonClient] ⏳ Waiting for daemon to start...")
            Thread.sleep(forTimeInterval: 2.0)
            UserDefaults.standard.set(true, forKey: installFlagKey)
            
            return true
        } catch {
            print("[DaemonClient] ❌ Installation failed: \(error)")
            return false
        }
    }
    
    /// Fetch power metrics from daemon cache (daemon runs powermetrics as root)
    func fetchPowerMetrics() -> PowerMetrics? {
        guard isDaemonRunning || startDaemon() else { return nil }
        guard let response = sendCommand("power") else { return nil }
        
        // Expected: "POWER CPU=12.3 GPU=4.5 DC=25.0 TS=1700000"
        var cpu: Double?
        var gpu: Double?
        var dc: Double?
        
        let parts = response.split(separator: " ")
        for part in parts {
            if part.hasPrefix("CPU=") {
                cpu = Double(part.dropFirst(4))
            } else if part.hasPrefix("GPU=") {
                gpu = Double(part.dropFirst(4))
            } else if part.hasPrefix("DC=") {
                dc = Double(part.dropFirst(3))
            }
        }
        return PowerMetrics(cpu: cpu, gpu: gpu, dc: dc)
    }
    
    /// Stream power metrics; caller manages lifecycle.
    func startPowerStream(onUpdate: @escaping (PowerMetrics) -> Void,
                          onError: @escaping () -> Void = {}) {
        stopPowerStream()
        powerStreamTask = Task.detached { [weak self] in
            guard let self else { return }
            
            let sock = socket(AF_UNIX, SOCK_STREAM, 0)
            guard sock >= 0 else { return }
            defer { close(sock) }
            
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            var pathBytes = Array(socketPath.utf8)
            if pathBytes.count >= MemoryLayout.size(ofValue: addr.sun_path) {
                pathBytes.removeLast(pathBytes.count - MemoryLayout.size(ofValue: addr.sun_path) + 1)
            }
            var sunPathCopy = addr.sun_path
            let sunPathSize = MemoryLayout.size(ofValue: sunPathCopy)
            withUnsafeMutableBytes(of: &sunPathCopy) { rawBuf in
                rawBuf.initializeMemory(as: UInt8.self, repeating: 0)
                let count = min(pathBytes.count, sunPathSize - 1)
                rawBuf.baseAddress?.copyMemory(from: pathBytes, byteCount: count)
            }
            addr.sun_path = sunPathCopy
            
            let connectResult = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connectResult == 0 else { return }
            
            // Send subscribe command
            let cmd = "power-stream\n"
            _ = cmd.withCString { cstr in
                send(sock, cstr, strlen(cstr), 0)
            }
            
            var buffer = [UInt8](repeating: 0, count: 1024)
            var partial = Data()
            
            while !Task.isCancelled {
                let readCount = read(sock, &buffer, buffer.count)
                if readCount <= 0 { break }
                
                partial.append(contentsOf: buffer.prefix(readCount))
                
                while let range = partial.firstRange(of: Data([0x0a])) { // newline
                    let lineData = partial.prefix(upTo: range.lowerBound)
                    partial = partial.suffix(from: range.upperBound)
                    if let line = String(data: lineData, encoding: .utf8) {
                        if let metrics = Self.parsePowerLine(line) {
                            await MainActor.run {
                                onUpdate(metrics)
                            }
                        }
                    }
                }
            }
            
            if Task.isCancelled { return }
            await MainActor.run { onError() }
        }
    }
    
    func stopPowerStream() {
        powerStreamTask?.cancel()
        powerStreamTask = nil
    }
    
    private nonisolated static func parsePowerLine(_ line: String) -> PowerMetrics? {
        guard line.hasPrefix("POWER") else { return nil }
        var cpu: Double?
        var gpu: Double?
        var dc: Double?
        line.split(separator: " ").forEach { part in
            if part.hasPrefix("CPU=") {
                cpu = Double(part.dropFirst(4))
            } else if part.hasPrefix("GPU=") {
                gpu = Double(part.dropFirst(4))
            } else if part.hasPrefix("DC=") {
                dc = Double(part.dropFirst(3))
            }
        }
        return PowerMetrics(cpu: cpu, gpu: gpu, dc: dc)
    }
    
    /// Execute installer tool with Authorization Services
    private func executeInstallerWithAuth(installerPath: String, helperBinary: String, plistFile: String) throws {
        let auth = try ensureAuthorization(allowPrompt: true)
        
        print("[DaemonClient] ✅ Authorization granted, executing installer...")
        
        // Execute installer with arguments: install_helper <helper_binary> <plist_file>
        var outputFile: UnsafeMutablePointer<FILE>? = nil
        
        let execStatus = installerPath.withCString { pathPtr in
            // Pass helper binary and plist paths as arguments
            let arg1 = strdup(helperBinary)
            let arg2 = strdup(plistFile)
            var args: [UnsafeMutablePointer<CChar>?] = [arg1, arg2, nil]
            
            defer {
                free(arg1)
                free(arg2)
            }
            
            return args.withUnsafeMutableBufferPointer { argsPtr in
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
                let pathMutable = UnsafeMutablePointer(mutating: pathPtr)
                
                return function(auth, pathMutable, [], argsPtr.baseAddress, &outputFile)
            }
        }
        
        guard execStatus == errAuthorizationSuccess else {
            throw NSError(domain: "DaemonClient", code: Int(execStatus),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to execute installer (code: \(execStatus))"])
        }
        
        // Read output from installer
        if let file = outputFile {
            let fileHandle = FileHandle(fileDescriptor: fileno(file))
            if let data = try? fileHandle.readToEnd(),
               let output = String(data: data, encoding: .utf8) {
                print("[DaemonClient] 📝 Installer output:")
                output.split(separator: "\n").forEach { line in
                    print("[DaemonClient]    \(line)")
                }
            }
            fclose(file)
        }
        
        print("[DaemonClient] ✅ Installer executed successfully")
    }
    
    /// Check if daemon is running with proper privileges
    func checkDaemon() {
        if let response = sendCommand("check") {
            // Check if daemon reports running as root (euid=0)
            if response.contains("euid=0") {
                print("[DaemonClient] ✅ Daemon running with root privileges: \(response)")
                isDaemonRunning = true
            } else {
                print("[DaemonClient] ⚠️ Daemon running but without root privileges: \(response)")
                // Kill non-privileged daemon
                killExistingDaemon()
                isDaemonRunning = false
            }
        } else {
            isDaemonRunning = false
        }
    }
    
    /// Kill existing daemon process
    private func killExistingDaemon() {
        print("[DaemonClient] Killing existing daemon...")
        // Try to remove socket file
        try? FileManager.default.removeItem(atPath: socketPath)
        
        // Kill daemon process by name
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-f", daemonPath]
        try? task.run()
        task.waitUntilExit()
        
        Thread.sleep(forTimeInterval: 0.3)
    }
    
    /// Attempt to start daemon if not running
    func startDaemon() -> Bool {
        print("[DaemonClient] Checking if daemon is running...")
        
        // First check if daemon is already running with proper privileges
        if let response = sendCommand("check") {
            if response.contains("euid=0") {
                print("[DaemonClient] ✅ Daemon already running with root privileges: \(response)")
                isDaemonRunning = true
                return true
            } else {
                print("[DaemonClient] ⚠️ Daemon running without root privileges, restarting...")
                killExistingDaemon()
            }
        }
        
        print("[DaemonClient] Daemon not running, attempting to start...")
        
        // Check if daemon file exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: daemonPath) {
            print("[DaemonClient] ❌ Daemon not installed at \(daemonPath)")
            
            // Try to install from bundle (only once)
            if !installAttempted {
                installAttempted = true
                print("[DaemonClient] Attempting auto-installation...")
                
                if installDaemonFromBundle() {
                    print("[DaemonClient] ✅ Daemon installed successfully")
                    // Continue to start daemon below
                } else {
                    print("[DaemonClient] ❌ Auto-installation failed")
                    return false
                }
            } else {
                print("[DaemonClient] ❌ Installation already attempted")
                return false
            }
        }

        // If helper is already installed (binary exists and previously authorized), avoid prompting again.
        if isHelperMarkedInstalled {
            // Give launchd a moment to (re)start it
            for _ in 0..<3 {
                Thread.sleep(forTimeInterval: 0.5)
                if let response = sendCommand("check"), response.contains("euid=0") {
                    print("[DaemonClient] ✅ Daemon came up without prompting")
                    isDaemonRunning = true
                    return true
                }
            }
            print("[DaemonClient] ⚠️ Daemon installed but not responding; skipping reprompt to avoid password loop")
            return false
        }
        
        // Try to start daemon using Authorization Services
        do {
            try startDaemonWithAuth()
            
            // Wait a bit for daemon to start
            Thread.sleep(forTimeInterval: 0.5)
            
            // Verify daemon started with proper privileges
            if let response = sendCommand("check") {
                if response.contains("euid=0") {
                    print("[DaemonClient] ✅ Daemon started successfully with root: \(response)")
                    isDaemonRunning = true
                    return true
                } else {
                    print("[DaemonClient] ❌ Daemon started but not as root: \(response)")
                    killExistingDaemon()
                    return false
                }
            } else {
                print("[DaemonClient] ❌ Daemon started but not responding")
                return false
            }
        } catch {
            print("[DaemonClient] ❌ Failed to start daemon: \(error)")
            return false
        }
    }
    
    /// Send command to daemon via Unix socket
    private func sendCommand(_ command: String) -> String? {
        print("[DaemonClient] 📤 Sending command: '\(command)' to socket \(socketPath)")
        
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            print("[DaemonClient] ❌ Failed to create socket (errno: \(errno))")
            return nil
        }
        defer { close(sock) }
        
        // Set socket timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        // Connect to daemon socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        // Copy socket path to avoid overlapping access
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        _ = socketPath.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { pathPtr in
                strncpy(pathPtr, cstr, pathSize)
            }
        }
        
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard connectResult == 0 else {
            // Daemon not running or not accessible
            print("[DaemonClient] ❌ Failed to connect to socket (errno: \(errno))")
            return nil
        }
        
        print("[DaemonClient] ✅ Connected to daemon socket")
        
        // Send command
        let commandData = command.data(using: .utf8)!
        let sendResult = commandData.withUnsafeBytes { bufferPtr in
            send(sock, bufferPtr.baseAddress, commandData.count, 0)
        }
        
        guard sendResult > 0 else {
            print("[DaemonClient] ❌ Failed to send command (errno: \(errno))")
            return nil
        }
        
        print("[DaemonClient] 📨 Sent \(sendResult) bytes, waiting for response...")
        
        // Receive response
        var buffer = [UInt8](repeating: 0, count: 1024)
        let recvResult = recv(sock, &buffer, buffer.count, 0)
        
        guard recvResult > 0 else {
            print("[DaemonClient] ❌ Failed to receive response (errno: \(errno), result: \(recvResult))")
            return nil
        }
        
        let response = String(bytes: buffer[..<recvResult], encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("[DaemonClient] 📥 Received response: '\(response ?? "nil")'")
        
        return response
    }
    
    /// Set fan speed via daemon
    func setFanSpeed(fan: Int, rpm: Int) throws {
        // Try with existing daemon first
        if isDaemonRunning {
            let command = "set-fan \(fan) \(rpm)"
            if let response = sendCommand(command) {
                if response.hasPrefix("OK") {
                    print("[DaemonClient] \(response)")
                    return
                } else {
                    print("[DaemonClient] ⚠️ Daemon returned error: \(response)")
                }
            } else {
                print("[DaemonClient] ⚠️ No response from daemon, marking as not running")
                isDaemonRunning = false
            }
        }
        
        // Daemon not running or failed, try to start it
        guard startDaemon() else {
            throw NSError(domain: "DaemonClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Daemon not available"])
        }
        
        // Retry with freshly started daemon
        let command = "set-fan \(fan) \(rpm)"
        guard let response = sendCommand(command) else {
            throw NSError(domain: "DaemonClient", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "No response from daemon"])
        }
        
        if !response.hasPrefix("OK") {
            throw NSError(domain: "DaemonClient", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: response])
        }
        
        print("[DaemonClient] \(response)")
    }
    
    /// Set manual mode via daemon
    func setManualMode(enabled: Bool) throws {
        // Try with existing daemon first
        if isDaemonRunning {
            let command = "set-mode \(enabled ? "1" : "0")"
            if let response = sendCommand(command) {
                if response.hasPrefix("OK") {
                    print("[DaemonClient] \(response)")
                    return
                } else {
                    print("[DaemonClient] ⚠️ Daemon returned error: \(response)")
                }
            } else {
                print("[DaemonClient] ⚠️ No response from daemon, marking as not running")
                isDaemonRunning = false
            }
        }
        
        // Daemon not running or failed, try to start it
        guard startDaemon() else {
            throw NSError(domain: "DaemonClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Daemon not available"])
        }
        
        // Retry with freshly started daemon
        let command = "set-mode \(enabled ? "1" : "0")"
        guard let response = sendCommand(command) else {
            throw NSError(domain: "DaemonClient", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "No response from daemon"])
        }
        
        if !response.hasPrefix("OK") {
            throw NSError(domain: "DaemonClient", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: response])
        }
        
        print("[DaemonClient] \(response)")
    }
    
    /// Start daemon with admin privileges using Authorization Services
    private func startDaemonWithAuth() throws {
        let auth = try ensureAuthorization(allowPrompt: true)
        
        // Execute daemon with privileges
        let execStatus = daemonPath.withCString { pathPtr in
            var args: [UnsafeMutablePointer<CChar>?] = [nil]
            
            return args.withUnsafeMutableBufferPointer { argsPtr in
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
                let pathMutable = UnsafeMutablePointer(mutating: pathPtr)
                
                return function(auth, pathMutable, [], argsPtr.baseAddress, nil)
            }
        }
        
        guard execStatus == errAuthorizationSuccess else {
            throw NSError(domain: "DaemonClient", code: Int(execStatus),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to execute daemon"])
        }
        
        print("[DaemonClient] Daemon execution started")
        UserDefaults.standard.set(true, forKey: installFlagKey)
    }

    private func ensureAuthorization(allowPrompt: Bool) throws -> AuthorizationRef {
        if let cachedAuth {
            return cachedAuth
        }

        var authRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw NSError(domain: "DaemonClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create authorization"])
        }

        let flags: AuthorizationFlags = allowPrompt
            ? [.interactionAllowed, .extendRights, .preAuthorize]
            : [.extendRights]

        let rightName = kAuthorizationRightExecute
        status = rightName.withCString { namePtr in
            var authItem = AuthorizationItem(name: namePtr, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &authItem) { itemPtr in
                var authRights = AuthorizationRights(count: 1, items: itemPtr)
                return AuthorizationCopyRights(auth, &authRights, nil, flags, nil)
            }
        }

        guard status == errAuthorizationSuccess else {
            AuthorizationFree(auth, [])
            throw NSError(domain: "DaemonClient", code: Int(status),
                         userInfo: [NSLocalizedDescriptionKey: "Authorization denied (code: \(status))"])
        }

        cachedAuth = auth
        return auth
    }
}
