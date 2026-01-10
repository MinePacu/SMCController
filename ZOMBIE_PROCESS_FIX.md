# Zombie Process Prevention

## Problem
Multiple daemon instances were being created, resulting in zombie processes:
```bash
root  58730  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper set-mode 0
root  58744  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper set-mode 1
root  57907  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
root  57071  /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
...
```

## Root Causes

### 1. No Instance Detection
- Daemon didn't check if another instance was already running
- Multiple `AuthorizationExecuteWithPrivileges` calls → multiple processes
- Each tried to bind to same socket → some failed but stayed alive

### 2. No PID File Locking
- No mechanism to prevent duplicate launches
- Race condition when starting daemon multiple times quickly

### 3. Socket State Confusion
- DaemonClient didn't verify socket before starting new daemon
- Old socket files weren't cleaned up properly

## Solution

### 1. Singleton Daemon (main_daemon.c)

Added **three layers of protection**:

#### Layer 1: Socket Connection Check
```c
static bool check_already_running(void) {
    // Try to connect to existing socket
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    // ... setup addr ...
    int result = connect(sock, (struct sockaddr*)&addr, sizeof(addr));
    close(sock);
    return (result == 0);  // If connect succeeds, daemon is running
}
```

#### Layer 2: PID File Locking
```c
static bool acquire_pidfile_lock(void) {
    g_pidfile_fd = open(PID_FILE, O_CREAT | O_RDWR, 0644);
    
    // Try to acquire exclusive lock
    struct flock fl;
    fl.l_type = F_WRLCK;  // Write lock
    // ... setup lock ...
    
    if (fcntl(g_pidfile_fd, F_SETLK, &fl) < 0) {
        // Lock failed - another instance is running
        return false;
    }
    
    // Write PID to file
    char pid_str[32];
    snprintf(pid_str, sizeof(pid_str), "%d\n", getpid());
    write(g_pidfile_fd, pid_str, strlen(pid_str));
    
    return true;
}
```

#### Layer 3: Signal Handlers
```c
static void signal_handler(int sig) {
    fprintf(stderr, "Received signal %d, shutting down...\n", sig);
    cleanup();
    exit(0);
}

// In main():
signal(SIGTERM, signal_handler);
signal(SIGINT, signal_handler);
signal(SIGHUP, signal_handler);
```

### 2. Main Function Protection
```c
int main(int argc, char* argv[]) {
    // 1. Check root
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR: Helper must run as root\n");
        return 1;
    }
    
    // 2. Check if already running (socket exists and responding)
    if (check_already_running()) {
        fprintf(stderr, "Daemon already running, exiting\n");
        return 0;  // Exit successfully, not an error
    }
    
    // 3. Acquire PID file lock
    if (!acquire_pidfile_lock()) {
        fprintf(stderr, "Another daemon instance is running, exiting\n");
        return 0;  // Exit successfully
    }
    
    // 4. Setup signal handlers
    signal(SIGTERM, signal_handler);
    
    // 5. Run daemon
    atexit(cleanup);
    run_daemon();
    
    return 0;
}
```

### 3. Enhanced Cleanup
```c
static void cleanup(void) {
    if (g_conn) {
        smc_close(g_conn);
        g_conn = NULL;
    }
    unlink(SOCKET_PATH);  // Remove socket
    
    // Release PID file lock and remove it
    if (g_pidfile_fd >= 0) {
        unlink(PID_FILE);
        close(g_pidfile_fd);
        g_pidfile_fd = -1;
    }
}
```

### 4. Client-Side Improvements (DaemonClient.swift)

Simplified connection logic:
```swift
func setFanSpeed(fan: Int, rpm: Int) throws {
    // Always try socket first (no isDaemonRunning check)
    if let response = sendCommand(command) {
        if response.hasPrefix("OK") {
            isDaemonRunning = true
            return
        }
    }
    
    // Socket failed, mark as not running and start
    isDaemonRunning = false
    guard startDaemon() else { throw error }
    
    // Retry
    guard let response = sendCommand(command) else { throw error }
    isDaemonRunning = true
}
```

## How It Works Now

### First Start
1. Client calls `setManualMode()` or `setFanSpeed()`
2. Socket doesn't exist → `sendCommand()` fails
3. `startDaemon()` called
4. Daemon checks: ❌ socket, ❌ PID lock → starts normally
5. Daemon creates socket + PID file
6. Client retries → ✅ succeeds

### Subsequent Calls
1. Client tries socket → ✅ succeeds immediately
2. No new daemon launched

### Duplicate Launch Attempt
1. Something tries to start second daemon
2. Daemon checks socket → ✅ connects successfully
3. Daemon exits with `return 0` (success)
4. **No zombie process created**

### PID File Locked
1. If socket check somehow fails but daemon is running
2. PID file lock acquisition fails
3. Daemon exits with `return 0`
4. **No zombie process created**

## Files Modified
- `SMCHelper/main_daemon.c`
  - Added `check_already_running()`
  - Added `acquire_pidfile_lock()`
  - Added `signal_handler()`
  - Enhanced `cleanup()`
  - Protected `main()` with checks

- `SMCController/DaemonClient.swift`
  - Simplified `setFanSpeed()` and `setManualMode()`
  - Always try socket first, no pre-checking
  - Update `isDaemonRunning` based on actual socket response

- `cleanup_daemon.sh`
  - Added PID file cleanup

## Testing

### Clean Install
```bash
./cleanup_daemon.sh
cd SMCHelper
./prepare_bundle.sh

# Xcode: Clean (⌘⇧K), Build (⌘B), Run (⌘R)
# Click Start → Stop → Start (repeat 10 times)
```

### Check for Zombies
```bash
# Should show max 1 daemon process
ps aux | grep SMCHelper | grep -v grep

# Should show PID file with single PID
cat /tmp/com.minepacu.SMCHelper.pid

# Should show socket
ls -l /tmp/com.minepacu.SMCHelper.socket
```

### Manual Test
```bash
# Try to start daemon manually (should exit immediately if already running)
sudo /Library/PrivilegedHelperTools/com.minepacu.SMCHelper

# Output should be:
# "Daemon already running, exiting"
# OR
# "Another daemon instance is running, exiting"
```

## Expected Behavior
✅ Only ONE daemon process at a time
✅ Duplicate launch attempts exit cleanly (no zombies)
✅ Socket always works if daemon is running
✅ Clean shutdown via signals
✅ PID file always reflects actual running daemon

## Debugging
```bash
# Check daemon status
./check_daemon.sh

# Manual socket test
echo "check" | nc -U /tmp/com.minepacu.SMCHelper.socket

# Clean everything
./cleanup_daemon.sh
```
