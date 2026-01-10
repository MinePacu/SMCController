# Rollback to Simple Version

## Why Rollback?
The zombie process prevention features (PID file locking, socket check) caused the daemon to freeze on startup.

**Error observed:**
```
[Swift SMC] ⚠️ Daemon unavailable, trying helper tool: Error Domain=DaemonClient Code=-3 "ERROR: Failed to set fan speed (error=-1)"
[HelperProxy] ✅ Helper found at /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
Daemon started, listening on /tmp/com.minepacu.SMCHelper.socket
```

Program would freeze completely.

## What Was Rolled Back

### main_daemon.c
Removed:
- `check_already_running()` function
- `acquire_pidfile_lock()` function
- `signal_handler()` function
- PID file management
- Signal handling setup

Back to simple version:
- Just socket server
- Basic cleanup on exit
- No instance checking

### DaemonClient.swift
Removed:
- "Always try socket first" logic
- Removed `isDaemonRunning` status updates in the setters

Back to original:
- Check `isDaemonRunning` flag first
- Only try socket if flag is true
- Mark as not running if socket fails

## Current State (Simple Version)

### Pros ✅
- Works reliably without freezing
- Daemon starts and responds properly
- Fan control functions work

### Cons ⚠️
- **Zombie processes can still occur**
- Multiple daemon instances possible
- No protection against duplicate launches

## Known Issues

### Zombie Processes
Running Start/Stop multiple times may create multiple daemon instances:
```bash
ps aux | grep SMCHelper
root  12345  SMCHelper
root  12346  SMCHelper
root  12347  SMCHelper
```

**Workaround:**
```bash
# Clean up manually
./cleanup_daemon.sh
```

### Helper Tool Conflict
When daemon fails, fallback to Helper Tool may:
1. Execute daemon binary with arguments
2. Daemon doesn't handle arguments
3. Creates zombie process

**Current behavior:** Tolerated as it still works via socket

## Next Steps (Future Work)

### Option 1: Debug Freeze Issue
Find out why PID locking caused freeze:
- Add more logging to daemon startup
- Check if SMC connection blocks during PID lock
- Test on different machines

### Option 2: Simpler Zombie Prevention
Instead of complex PID locking:
- Just kill existing process before starting new one
- Use `pkill -9` in DaemonClient before `startDaemonWithAuth()`
- Less elegant but might work

### Option 3: Use launchd Properly
Let launchd manage the daemon:
- Set `KeepAlive = true` in plist
- Never manually start with AuthorizationExecuteWithPrivileges
- Use `launchctl load/unload` only

## Testing Current Version

```bash
# Clean install
./cleanup_daemon.sh
cd SMCHelper
./prepare_bundle.sh

# Xcode: ⌘⇧K, ⌘B, ⌘R
# Test Start/Stop multiple times

# Check for zombies after testing
ps aux | grep SMCHelper | grep -v grep

# If zombies appear, clean up:
./cleanup_daemon.sh
```

## Files Modified
- `SMCHelper/main_daemon.c` - Reverted to simple version
- `SMCController/DaemonClient.swift` - Reverted to original logic
- `SMCHelper/SMCHelper` - Rebuilt binary (52KB, simpler)

## Files Preserved
- `ZOMBIE_PROCESS_FIX.md` - Kept for reference (ideas for future)
- `cleanup_daemon.sh` - Still useful for manual cleanup
- All other files unchanged
