# SMCController

SwiftUI app to control macOS fans through SMC. Supports Apple Silicon and Intel, offers custom curves, sensor monitoring, PID tuning, and delegates privileged work to the bundled SMCHelper daemon.

> Looking for Korean? See `Readme_ko.md`.

## Highlights
- Fan curve editor + PID: edit temperature/RPM points in graph/table and apply on the fly with `Apply`
- Sensor monitoring: CPU/GPU/fan RPM, SMC sensor debug, Apple Silicon HID sensor debug views
- Privilege flow: installs bundled SMCHelper to `/Library/PrivilegedHelperTools/com.minepacu.SMCHelper` via Authorization Services; communicates over Unix socket `/tmp/com.minepacu.SMCHelper.socket`
- Convenience: monitor-only mode, auto-load min/max RPM, fan index selection, extra sensor key monitoring
- Scripts: `build_and_test.sh`, `check_daemon.sh`, `cleanup_daemon.sh` for build/status/cleanup; `SMCHelper/update_installed_helper.sh` to rebuild and reinstall the helper daemon

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
  - Curve behavior: linear interpolation between points; below the lowest temp uses min RPM, above the highest temp uses max RPM. Keep at least two points, up to twelve.  
  - PID: optional; start with Target near your preferred CPU temp (e.g., 70°C) and Kp≈50, Ki=0, Kd=0. Increase Kp if too hot, reduce if oscillating.  
  - Interval: default 1.0s; avoid dropping below 0.2s to prevent jitter and excess load.  
  - Use `Start` to control, `Monitor Only` for read-only, `Apply` to push changes while running, `Stop` to return to automatic mode.
- Debug/Status: HID Sensors, SMC Sensors, Privileges tabs for live readings and privilege checks.
- Privileges (inlined because the separate guides are gitignored): the app stays unprivileged; the first control attempt triggers an Authorization Services prompt to install/run SMCHelper. If auto install fails, open the Privileges tab, copy the suggested terminal command, and run it in a shell to elevate; you can also run `sudo /Applications/SMCController.app/Contents/MacOS/SMCController` manually. Helper fallback is disabled—daemon must be present for control.

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
- Helper reinstall/refresh (rebuild + copy to /Library and reload launchd):
```bash
cd SMCHelper
./update_installed_helper.sh
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
- Docs visibility: `.gitignore` excludes `*.md` except README. If these guides are missing in your clone, fetch them from the original source or add per-file exceptions in `.gitignore` before committing.
