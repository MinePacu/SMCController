# SMCController

SwiftUI-based macOS fan control app for Intel and Apple Silicon Macs that expose SMC fan control.

[한국어 문서 바로가기](README.ko.md)

## Overview

SMCController provides a desktop UI for:

- monitoring temperatures, fan RPM, and selected power metrics
- editing custom fan curves
- optionally tuning fan behavior with PID values
- saving and loading named presets
- enabling privileged fan-write access only when it is actually needed

The app stays unprivileged for normal monitoring. The helper daemon is installed or started only when you explicitly enable fan control from the `Privileges` screen or attempt a control path that requires it.

## Current Features

### Fan Control

- custom fan curve editor with graph and point list
- min/max RPM refresh from hardware
- dynamic fan index selection based on detected fan count
- optional PID tuning with target temperature, `Kp`, `Ki`, and `Kd`
- monitor-only mode and active control mode

### Monitoring

- current temperature and applied RPM display
- extra SMC sensor key monitoring
- Apple Silicon HID sensor diagnostics
- SMC sensor diagnostics
- daemon-backed power metrics when available

### Presets and Persistence

- automatic restore of the last used settings
- named preset save, load, update, and delete
- persistence for curve points, PID values, sensor keys, fan index, and interval

### Privilege Flow

- no automatic privilege prompt on first launch
- helper status screen for install/start checks
- one-button helper enable flow when manual fan control is needed

## App Navigation

The current sidebar structure is:

- `Fan Control`
- `Privileges`
- `Presets`
- `Diagnostics`
  - `HID Sensors`
  - `SMC Sensors`

`About` is available from the macOS app menu instead of the sidebar.

## Project Structure

```text
SMCController/
├── App/                # app entry point, root navigation, assets
├── Core/
│   ├── Controllers/    # fan control loop and control-facing APIs
│   ├── Models/         # shared data and policy types
│   └── Services/       # helper, sensor, daemon, and system-facing services
├── Features/
│   ├── About/
│   ├── Diagnostics/
│   ├── FanControl/
│   ├── Presets/
│   └── Privileges/
├── Platform/           # SMC/HID bridge and low-level platform integration
└── Support/            # backup or support files
```

## Requirements

- macOS 14 or later
- Xcode 15 or later
- a Mac that exposes the relevant SMC or HID data paths
- a local administrator account if you want to enable privileged fan control

## Build and Run

### 1. Prepare helper resources

This app expects the bundled helper resources used by `DaemonClient`:

- `SMCHelper`
- `install_helper`
- `com.minepacu.SMCHelper.plist`

If you are building from source, prepare and include those bundle resources before relying on privileged fan control.

### 2. Open and build

- Open `SMCController.xcodeproj` in Xcode.
- Build the app with the default scheme.

### 3. Launch

- Run the app normally.
- Monitoring features can work without elevated privileges.
- Open `Privileges` and use `Enable Fan Control` when you want helper-backed write access.

## Typical Usage

1. Open `Fan Control`.
2. Choose the sensor key to drive the curve.
3. Refresh min/max RPM if needed.
4. Adjust curve points.
5. Optionally enable PID tuning.
6. Save the setup as a preset.
7. Open `Privileges` and enable helper access if you want manual fan writes.
8. Start fan control or use monitor-only behavior depending on your workflow.

## Notes and Cautions

- Manual fan control can override the system thermal policy.
- Apple Silicon fan control support depends on hardware exposure and helper availability.
- If readings or behavior look wrong, stop control and return to automatic mode.
- Sensor availability differs across Mac models.

## Main Source Areas

- [SMCController/App/ContentView.swift](SMCController/App/ContentView.swift)
- [SMCController/App/SMCControllerApp.swift](SMCController/App/SMCControllerApp.swift)
- [SMCController/Features/FanControl/FanControlView.swift](SMCController/Features/FanControl/FanControlView.swift)
- [SMCController/Features/FanControl/FanControlViewModel.swift](SMCController/Features/FanControl/FanControlViewModel.swift)
- [SMCController/Features/Privileges/PrivilegeStatusView.swift](SMCController/Features/Privileges/PrivilegeStatusView.swift)
- [SMCController/Core/Services/DaemonClient.swift](SMCController/Core/Services/DaemonClient.swift)
- [SMCController/Platform/SMC.swift](SMCController/Platform/SMC.swift)

## License

No license file is currently included in this repository. Add one before distributing the project outside its current intended scope.
