//
//  PrivilegeHelper.swift
//  SMCController
//
//  Simple privilege management without complex helper tools
//

import Foundation
import Security
import AppKit
import Combine

@MainActor
class PrivilegeHelper: ObservableObject {
    static let shared = PrivilegeHelper()
    
    @Published var hasPrivileges = false
    @Published var showPrivilegeAlert = false
    @Published var elevationAttempted = false
    
    private var installRetryCount = 0
    private let maxInstallRetries = 2
    
    private init() {
        checkPrivileges()
    }
    
    /// Check if we're running with root privileges
    static func isRunningAsRoot() -> Bool {
        return geteuid() == 0
    }
    
    /// Check if app has necessary privileges for SMC access
    func checkPrivileges() {
        // Don't check if running as root - we want to use daemon instead
        // Just check if daemon is available
        print("[PrivilegeHelper] Checking daemon availability...")
        
        let daemonAvailable = DaemonClient.shared.startDaemon()
        
        if daemonAvailable {
            print("[PrivilegeHelper] ✅ Daemon available for SMC operations")
            hasPrivileges = true
            showPrivilegeAlert = false
        } else {
            print("[PrivilegeHelper] ⚠️ Daemon not available")
            hasPrivileges = false
            showPrivilegeAlert = true
        }
    }
    
    /// Attempt to start daemon instead of relaunching app
    func requestPrivilegesAndRelaunch() {
        guard !elevationAttempted else {
            print("[PrivilegeHelper] Elevation already attempted, not trying again")
            return
        }
        
        // Check retry limit
        if installRetryCount >= maxInstallRetries {
            print("[PrivilegeHelper] ❌ Max install retries (\(maxInstallRetries)) reached")
            showFinalFailureMessage()
            return
        }
        
        elevationAttempted = true
        installRetryCount += 1
        
        print("[PrivilegeHelper] Requesting daemon start (attempt \(installRetryCount)/\(maxInstallRetries))...")
        
        // Try to start daemon
        if DaemonClient.shared.startDaemon() {
            print("[PrivilegeHelper] ✅ Daemon started successfully")
            hasPrivileges = true
            showPrivilegeAlert = false
            installRetryCount = 0  // Reset on success
        } else {
            print("[PrivilegeHelper] ❌ Failed to start daemon (attempt \(installRetryCount)/\(maxInstallRetries))")
            
            // Reset flag to allow retry, but check count
            elevationAttempted = false
            
            if installRetryCount < maxInstallRetries {
                showRunInstructions()
            } else {
                showFinalFailureMessage()
            }
        }
    }
    
    /// Show instructions if auto-install fails
    func showRunInstructions() {
        // Show alert about daemon installation
        let alert = NSAlert()
        alert.messageText = "SMC Helper Required"
        alert.informativeText = """
        SMCController needs to install a helper daemon to control fan speeds.
        
        The daemon will be installed automatically when you grant permission.
        
        • You'll be asked for your password once
        • The daemon runs in the background with admin privileges
        • Your app runs normally without admin privileges
        • Fan control works seamlessly without repeated password prompts
        
        The helper daemon will be installed at:
        /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
        
        Attempt \(installRetryCount) of \(maxInstallRetries)
        
        Click "Install Helper" to proceed, or "Skip" to continue without fan control.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Helper")
        alert.addButton(withTitle: "Skip")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // User wants to install, try again
            requestPrivilegesAndRelaunch()
        } else {
            // Continue without privileges - fan control won't work
            showPrivilegeAlert = false
            installRetryCount = 0  // Reset for next time
        }
    }
    
    /// Show final failure message with manual instructions
    func showFinalFailureMessage() {
        let alert = NSAlert()
        alert.messageText = "Helper Installation Failed"
        alert.informativeText = """
        The automatic installation has failed after \(maxInstallRetries) attempts.
        
        This may be because:
        • The installation files are not included in the app bundle
        • Permission was denied
        • A system security setting is blocking the installation
        
        To install manually, open Terminal and run:
        
        cd /path/to/SMCController/SMCHelper
        sudo ./install_daemon.sh
        
        Or continue without fan control capabilities.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Continue Without Helper")
        
        let response = alert.runModal()
        
        showPrivilegeAlert = false
        installRetryCount = 0  // Reset for next app launch
    }
}

// Extension to test SMC write access
extension SMCService {
    static func testSMCWriteAccess() -> Bool {
        // First check: Are we running as root?
        let isRoot = geteuid() == 0
        print("[SMCService] Running as root: \(isRoot) (euid=\(geteuid()))")
        
        if !isRoot {
            print("[SMCService] ❌ Not running as root - SMC write will fail")
            return false
        }
        
        // Second check: Can we actually open SMC?
        do {
            let testService = try SMCService()
            
            // Third check: Try to read fan count
            let fanCount = try testService.fanCount()
            print("[SMCService] Fan count: \(fanCount)")
            
            // Fourth check: Actually test write access by trying to read a fan control key
            // We don't actually write, but check if the write-related keys are accessible
            if fanCount > 0 {
                do {
                    // Try to read current target RPM (F0Tg) - this is a write-controlled key
                    let currentTarget = try testService.targetRPM(fan: 0)
                    print("[SMCService] ✅ Can read fan control keys (F0Tg=\(currentTarget))")
                    
                    // If we can read the target RPM key, we likely have write access
                    // but let's verify with the actual SMC connection handle
                    guard let handle = testService.connection else {
                        print("[SMCService] ❌ No SMC connection handle")
                        return false
                    }
                    
                    // Test actual write capability by checking IOKit connection privileges
                    let result = smc_check_write_access(handle)
                    if result == 0 {
                        print("[SMCService] ✅ SMC write access verified")
                        return true
                    } else {
                        print("[SMCService] ❌ SMC write access check failed: \(result)")
                        return false
                    }
                } catch {
                    print("[SMCService] ⚠️ Cannot read fan control keys: \(error)")
                    // If running as root but can't read control keys, we don't have write access
                    return false
                }
            } else {
                print("[SMCService] ⚠️ No fans detected")
                return false
            }
        } catch {
            print("[SMCService] ❌ Failed to access SMC: \(error)")
            return false
        }
    }
}
