# SMCController

SwiftUI app to control macOS fans through SMC. Supports Apple Silicon and Intel, offers custom curves, sensor monitoring, PID tuning, and delegates privileged work to the bundled SMCHelper daemon.

> Looking for Korean? See `Readme_ko.md`.

## Highlights
- Fan curve editor + PID: edit temperature/RPM points in graph/table and apply on the fly with `Apply`
- Sensor monitoring: CPU/GPU/fan RPM, SMC sensor debug, Apple Silicon HID sensor debug views
- Privilege flow: installs bundled SMCHelper to `/Library/PrivilegedHelperTools/com.minepacu.SMCHelper` via Authorization Services; communicates over Unix socket `/tmp/com.minepacu.SMCHelper.socket`
- Convenience: monitor-only mode, auto-load min/max RPM, fan index selection, extra sensor key monitoring
- Scripts: `build_and_test.sh`, `check_daemon.sh`, `cleanup_daemon.sh` for build/status/cleanup

## Architecture
- SwiftUI app (`SMCController/`): UI, `FanController` loop, `FanPolicy`, `FanCurveEditorView`, etc.
- SMC/HID bridge (`SMCBridge.c`, `SMCHID.m`, `SMCAppleSilicon.swift`): direct hardware calls
- Privileged daemon (`SMCHelper/main_daemon.c`) & installer tool (`install_helper.c`): copied from bundle and run as LaunchDaemon
- Privilege helpers (`DaemonClient.swift`, `PrivilegeHelper.swift`): install/run the daemon and check privileges

## Requirements
- macOS 14+ / Xcode 15+ (uses Swift Observation)
- Local admin account: one-time password prompt when installing the daemon
- Build tools: Xcode command line tools, clang

## Quick Start (from source)
1) Build SMCHelper bundle assets  
```bash
cd SMCHelper
./prepare_bundle.sh
```
Produces `SMCHelper`, `install_helper`, `com.minepacu.SMCHelper.plist`.

2) Add resources to Xcode  
- `File → Add Files...` and include the three files above (Copy items if needed, Target: SMCController).  
- Ensure they are in `Build Phases → Copy Bundle Resources` and **not** in `Compile Sources`.  
- Details: `BUILD_AND_TEST.md`, `PREBUILT_BINARY_INSTALL.md`.

3) Build  
- Xcode: `Product → Clean Build Folder` then `Build`.  
- CLI: `./build_and_test.sh` (Release, codesign disabled).

4) Run  
- Launch the built `SMCController.app` (`build/Build/Products/Release/SMCController.app` or Xcode Run).  
- When fan control starts, Authorization Services prompts for a password and installs the daemon to `/Library/PrivilegedHelperTools/com.minepacu.SMCHelper`.

5) Verify  
```bash
./check_daemon.sh
```

## Usage
- Run the app as a normal user (no sudo). If the daemon is missing, the app attempts installation.
- Fan Control tab:  
  - Sensor key: Intel defaults to `TC0P`, Apple Silicon auto-detects (`Tp09`). Add extra monitor keys comma-separated.  
  - Fan index and min/max RPM are read from hardware; refresh via `Refresh Fan Limits`.  
  - Edit curve points or enable PID (Target/Kp/Ki/Kd) as needed.  
  - `Start` to control, `Monitor Only` for read-only, `Apply` to push changes while running, `Stop` to return to automatic mode.
- Debug/Status: HID Sensors, SMC Sensors, Privileges tabs.  
- More UX/tuning tips: `FAN_CONTROL_GUIDE.md`, `PRIVILEGE_GUIDE.md`.

## Daemon Management
- Manual install/reinstall:
```bash
cd SMCHelper
sudo ./install_daemon.sh
```
- Cleanup and retest:
```bash
./cleanup_daemon.sh
./check_daemon.sh
```
- If the daemon is missing or fails, fan control returns errors (Helper fallback disabled). Last resort run as root:
```bash
sudo /Applications/SMCController.app/Contents/MacOS/SMCController
```

## Additional Docs
- `AUTO_INSTALL_GUIDE.md` automatic install flow
- `DAEMON_USAGE.md`, `PRIVILEGE_SEPARATION.md` privilege/architecture notes
- `TROUBLESHOOT_INSTALL.md`, `DAEMON_START_FIX.md`, `ZOMBIE_PROCESS_FIX.md` troubleshooting
- `XCODE_SETUP.md` bundle inclusion, `ROLLBACK_NOTE.md`, `REBUILD_REQUIRED.md` for regressions
