//
//  SMCHelperProxy.swift
//  SMCController
//
//  Proxy for communicating with privileged helper tool
//

import Foundation
import Security

class SMCHelperProxy {
    static let shared = SMCHelperProxy()
    
    private let helperPath = "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
    var isInstalled = false  // Changed to internal
    
    private init() {
        checkInstallation()
    }
    
    /// Check if helper is installed and working
    func checkInstallation() {
        let fm = FileManager.default
        
        // First check: Does file exist?
        isInstalled = fm.fileExists(atPath: helperPath)
        
        if !isInstalled {
            print("[HelperProxy] Helper not installed at \(helperPath)")
            return
        }
        
        // Second check: Is it executable?
        guard fm.isExecutableFile(atPath: helperPath) else {
            print("[HelperProxy] Helper exists but is not executable")
            isInstalled = false
            return
        }
        
        print("[HelperProxy] ✅ Helper found at \(helperPath)")
        
        // We assume it works if it exists and is executable
        // Actual execution test would require password prompt
        isInstalled = true
    }
    
    /// Install helper tool (requires admin password)
    func installHelper() throws {
        print("[HelperProxy] Installing helper tool...")
        
        // Get path to build script
        guard let buildScriptPath = Bundle.main.path(forResource: "build", ofType: "sh", inDirectory: "SMCHelper") else {
            throw NSError(domain: "SMCHelper", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Build script not found in bundle"])
        }
        
        // Run build script with admin privileges
        let script = """
        do shell script "cd '\(buildScriptPath.deletingLastPathComponent)' && ./build.sh" with administrator privileges
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                throw NSError(domain: "SMCHelper", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Installation failed: \(error)"])
            }
            
            print("[HelperProxy] Installation result: \(result.stringValue ?? "success")")
            checkInstallation()
        } else {
            throw NSError(domain: "SMCHelper", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript"])
        }
    }
    
    /// Run helper with arguments using Authorization Services
    private func runHelper(args: [String]) throws -> String {
        // Use AuthorizationExecuteWithPrivileges to run without password each time
        var authRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authRef)
        
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw NSError(domain: "SMCHelper", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create authorization"])
        }
        
        defer {
            AuthorizationFree(auth, [])
        }
        
        // Request authorization (may prompt for password first time)
        let rightName = kAuthorizationRightExecute
        status = rightName.withCString { namePtr in
            var authItem = AuthorizationItem(name: namePtr, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &authItem) { itemPtr in
                var authRights = AuthorizationRights(count: 1, items: itemPtr)
                return AuthorizationCopyRights(auth, &authRights, nil, 
                                              [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        
        guard status == errAuthorizationSuccess else {
            throw NSError(domain: "SMCHelper", code: Int(status),
                        userInfo: [NSLocalizedDescriptionKey: "Authorization denied"])
        }
        
        // Execute helper with privileges
        let pipe = Pipe()
        var outputFile: UnsafeMutablePointer<FILE>? = nil
        
        let execStatus = helperPath.withCString { pathPtr in
            // Convert args to C strings
            let cArgs = args.map { strdup($0) } + [nil]
            defer { cArgs.forEach { if let ptr = $0 { free(ptr) } } }
            
            return cArgs.withUnsafeBufferPointer { argsPtr in
                // Call the deprecated but working function
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
            throw NSError(domain: "SMCHelper", code: Int(execStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Failed to execute helper"])
        }
        
        // Read output from pipe
        var output = ""
        if let file = outputFile {
            let fileHandle = FileHandle(fileDescriptor: fileno(file))
            if let data = try? fileHandle.readToEnd(),
               let str = String(data: data, encoding: .utf8) {
                output = str
            }
            fclose(file)
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Set fan RPM
    func setFanRPM(fan: Int, rpm: Int) throws {
        guard isInstalled else {
            throw NSError(domain: "SMCHelper", code: -100,
                        userInfo: [NSLocalizedDescriptionKey: "Helper not installed"])
        }
        
        let result = try runHelper(args: ["set-fan", "\(fan)", "\(rpm)"])
        print("[HelperProxy] \(result)")
    }
    
    /// Set manual mode
    func setManualMode(enabled: Bool) throws {
        guard isInstalled else {
            throw NSError(domain: "SMCHelper", code: -100,
                        userInfo: [NSLocalizedDescriptionKey: "Helper not installed"])
        }
        
        let result = try runHelper(args: ["set-mode", enabled ? "1" : "0"])
        print("[HelperProxy] \(result)")
    }
    
    /// Get current fan RPM
    func getCurrentRPM(fan: Int) throws -> Int {
        guard isInstalled else {
            throw NSError(domain: "SMCHelper", code: -100,
                        userInfo: [NSLocalizedDescriptionKey: "Helper not installed"])
        }
        
        let result = try runHelper(args: ["get-rpm", "\(fan)"])
        print("[HelperProxy] \(result)")
        
        // Parse output: "OK: Fan 0 current RPM: 1001"
        if let rpmString = result.components(separatedBy: ": ").last,
           let rpm = Int(rpmString) {
            return rpm
        }
        
        return 0
    }
}

extension String {
    func deletingLastPathComponent() -> String {
        return (self as NSString).deletingLastPathComponent
    }
}
