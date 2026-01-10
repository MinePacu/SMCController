# Helper Tool Temporarily Disabled

## Change Summary
Helper Tool fallback has been **temporarily disabled** in `SMC.swift`. Only Daemon socket communication is active.

## Why Disabled?

### Problem: Two conflicting execution modes
The codebase has two different ways to run the same binary (`/Library/PrivilegedHelperTools/com.minepacu.SMCHelper`):

1. **Daemon Mode (DaemonClient)** ✅ Active
   - Runs as background daemon via launchctl
   - Listens on Unix socket: `/tmp/com.minepacu.SMCHelper.socket`
   - Persistent process handling multiple requests
   - Communication: `echo "check" | nc -U /tmp/socket`

2. **Helper Tool Mode (SMCHelperProxy)** ❌ Disabled
   - Runs via `AuthorizationExecuteWithPrivileges`
   - Executes once per command with arguments
   - Terminates immediately after command
   - Communication: `SMCHelper set-mode 1`

### The Conflict
When daemon fails, SMC.swift falls back to Helper Tool which:
1. Executes the **daemon binary** with command-line arguments
2. But `main_daemon.c` **doesn't handle arguments** - it only runs socket server
3. Process starts, doesn't understand args, fails
4. Multiple daemon instances pile up (seen in `ps aux`)

### Observed Symptoms
```
root  58730  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper set-mode 0
root  58744  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper set-mode 1
root  57907  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
root  57071  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
...
```

Multiple instances running, some as socket server, some as failed helper attempts.

## What Changed

### Before
```swift
// Try daemon
try DaemonClient.shared.setManualMode(enabled)

// Fallback to helper tool
if SMCHelperProxy.shared.isInstalled {
    try SMCHelperProxy.shared.setManualMode(enabled)
}

// Fallback to direct SMC
let h = try requireHandle()
smc_set_fan_manual(h, enabled)
```

### After
```swift
// Try daemon ONLY
do {
    try DaemonClient.shared.setManualMode(enabled)
    return
} catch {
    // Re-throw error, no fallback
    throw error
}

// Helper tool code commented out but preserved
/* ... commented helper tool code ... */
```

## Files Modified
- `SMCController/SMC.swift`
  - `setTargetRPM()` - Helper fallback disabled
  - `setManualMode()` - Helper fallback disabled

## Files Preserved (NOT deleted)
- `SMCController/SMCHelperProxy.swift` - Kept for future use
- All Authorization Services code
- All helper tool infrastructure

## Current Behavior
1. ✅ Start → Daemon socket communication → Works
2. ✅ Stop → Daemon socket communication → Works
3. ❌ Daemon fails → Error shown, no fallback
4. ✅ No more zombie daemon processes

## Future Solutions

### Option 1: Dual-mode daemon
Modify `main_daemon.c` to support both modes:
```c
int main(int argc, char *argv[]) {
    if (argc > 1) {
        // Helper mode: execute command and exit
        return handle_command_args(argc, argv);
    } else {
        // Daemon mode: run socket server
        return run_daemon_server();
    }
}
```

### Option 2: Separate binaries
- `SMCHelper` - Daemon (socket server)
- `SMCHelperTool` - One-shot helper (command executor)

### Option 3: Remove Helper Tool entirely
- Only use Daemon socket communication
- Delete SMCHelperProxy and related code

## Testing
```bash
# Clean old daemon instances
sudo pkill -f SMCHelper
sudo launchctl unload /Library/LaunchDaemons/com.minepacu.SMCHelper.plist 2>/dev/null
sudo rm -f /tmp/com.minepacu.SMCHelper.socket

# Restart app and test
# Should work via daemon only
# Check for zombie processes
ps aux | grep SMCHelper
```

## Rollback
To re-enable helper tool fallback, uncomment the sections in `SMC.swift` marked with:
```swift
// DISABLED: Helper tool conflicts with daemon socket communication
```
