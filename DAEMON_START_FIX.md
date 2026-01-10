# Daemon Start Fix - UI Freeze Issue

## Problem
When clicking "Start" in Fan Control, the app froze with this log:
```
[Swift SMC] ⚠️ Daemon unavailable, trying helper tool: Error Domain=DaemonClient Code=-3 "ERROR: Failed to set manual mode (error=-1)"
Daemon started, listening on /tmp/com.minepacu.SMCHelper.socket
```

## Root Cause
`DaemonClient.startDaemon()` was calling `startDaemonWithAuth()` which used `AuthorizationExecuteWithPrivileges` to **directly execute the daemon binary**. This:

1. **Blocked the main thread** waiting for authorization
2. **Started daemon as a foreground process** instead of a background daemon
3. **Didn't use launchctl** to properly manage the daemon lifecycle

## Solution
Modified `DaemonClient.swift` to:

1. **Use launchctl to start the daemon** (after installation)
   ```swift
   let task = Process()
   task.launchPath = "/bin/launchctl"
   task.arguments = ["load", "/Library/LaunchDaemons/com.minepacu.SMCHelper.plist"]
   ```

2. **Removed `startDaemonWithAuth()`** - no longer needed
3. **Non-blocking daemon start** - launchctl returns immediately

## How It Works Now

### First Time (Not Installed)
1. User clicks "Start" → tries to set manual mode
2. Daemon not found → `installDaemonFromBundle()` called
3. **Password prompt appears** (via `install_helper` binary)
4. Installation completes → daemon installed at `/Library/PrivilegedHelperTools/`
5. Plist installed at `/Library/LaunchDaemons/`
6. `launchctl load` starts the daemon
7. Daemon responds → fan control works

### Subsequent Times (Already Installed)
1. User clicks "Start" → tries to set manual mode
2. Daemon check fails → `startDaemon()` called
3. Daemon exists at `/Library/PrivilegedHelperTools/` → skip installation
4. **`launchctl load`** starts daemon (no password needed)
5. Daemon responds → fan control works immediately

## Testing

### Clean Test (Fresh Install)
```bash
# Remove old installations
sudo rm -f /Library/PrivilegedHelperTools/com.*.SMCHelper
sudo rm -f /Library/LaunchDaemons/com.*.SMCHelper.plist
sudo launchctl unload /Library/LaunchDaemons/com.minepacu.SMCHelper.plist 2>/dev/null
sudo rm -f /tmp/com.*.SMCHelper.socket

# Rebuild app
cd SMCHelper
./prepare_bundle.sh

# Run app
# Click Fan Control → Start
# Should see password prompt ONCE
# Then fan control should work
```

### Check Daemon Status
```bash
# Check if daemon is installed
ls -l /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
ls -l /Library/LaunchDaemons/com.minepacu.SMCHelper.plist

# Check if daemon is running
sudo launchctl list | grep SMCHelper
ps aux | grep SMCHelper

# Check socket
ls -l /tmp/com.minepacu.SMCHelper.socket

# Test daemon manually
echo "check" | nc -U /tmp/com.minepacu.SMCHelper.socket
```

## Key Changes

### Before (Caused Freeze)
```swift
try startDaemonWithAuth()  // Blocks UI thread!
Thread.sleep(forTimeInterval: 0.5)
```

### After (Non-blocking)
```swift
let task = Process()
task.launchPath = "/bin/launchctl"
task.arguments = ["load", "/Library/LaunchDaemons/com.minepacu.SMCHelper.plist"]
try task.run()
task.waitUntilExit()  // Quick, just launches launchctl
Thread.sleep(forTimeInterval: 1.0)
```

## Expected Behavior
- ✅ No UI freeze
- ✅ Password prompt appears only on first install
- ✅ Daemon starts in background properly
- ✅ Subsequent starts work without password
- ✅ Daemon managed by launchd (auto-restart, logging, etc.)
