# Privilege Separation - Daemon Only Architecture

## Summary
**Helper Tool fallback has been permanently disabled** to prevent zombie processes and freezes.
The app now uses **daemon-only architecture** via Unix socket communication.

## Problem Solved

### Issue: Stop Button Freezes App
```
[Swift SMC] ⚠️ Daemon unavailable, trying helper tool: Error Domain=DaemonClient Code=-3
[HelperProxy] ✅ Helper found at /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
Daemon started, listening on /tmp/com.minepacu.SMCHelper.socket
<APP FREEZES>
```

### Root Cause
1. Stop button calls `setManualMode(false)`
2. Daemon socket fails (for some reason)
3. Falls back to `SMCHelperProxy`
4. Executes: `SMCHelper set-mode 0` (with arguments)
5. **Binary is daemon, not helper!** Doesn't handle args
6. Tries to start socket server but socket exists
7. **Process hangs forever = freeze**

## Solution

### 1. Disable Helper Tool Fallback
**File: `SMCController/SMC.swift`**

Changed from 3-tier fallback to daemon-only:
```swift
// BEFORE
try daemon → try helper tool → try direct SMC

// AFTER  
try daemon → throw error if fails (no fallback)
```

### 2. Ignore Stop Errors
**File: `SMCController/FanController.swift`**

Stop should always succeed even if daemon fails:
```swift
func stop() async {
    task?.cancel()
    isRunning = false
    
    // Best-effort (don't fail if daemon is down)
    do {
        try await smc.setManualMode(false)
    } catch {
        print("⚠️ Failed to disable manual mode (ignoring)")
    }
}
```

### 3. Enhanced Logging
**File: `SMCController/DaemonClient.swift`**

Added detailed socket communication logs for debugging.

## Testing

```bash
# Clean zombies
./cleanup_daemon.sh

# Rebuild & Run
⌘⇧K → ⌘B → ⌘R

# Test repeatedly
Start → Stop → Start → Stop (10 times)

# Check processes
ps aux | grep SMCHelper | grep -v grep
# Should show ONLY one daemon (no arguments)
```

## Expected Behavior

✅ **Start button:** Daemon starts, fan control works
✅ **Stop button:** No freeze, control loop stops immediately  
✅ **No zombies:** Only one daemon process
✅ **Logs clear:** Socket communication visible in console

## Files Modified
- `SMCController/SMC.swift` - Daemon only, no Helper fallback
- `SMCController/FanController.swift` - Ignore stop errors
- `SMCController/DaemonClient.swift` - Enhanced logging
