# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Custom fan curve editor with optional PID tuning and named presets.
- Privileged helper exposed as an XPC Mach service with a lease-based watchdog
  that returns fans to automatic mode if the app stops renewing it.
- English, Korean, and Japanese localization with an in-app language setting.
- Appearance-aware app icons.
- `LICENSE`, `CHANGELOG.md`, and `CONTRIBUTING.md`.
- Configurable critical temperature that stops manual control and returns fans
  to automatic mode.
- Implausible sensor readings now stop manual control.
- Hysteresis and ramp-down limiting so fan speed no longer bounces near curve points.
- Automatic mode is restored before system sleep and on quit; control resumes after wake.
- Menu bar item with live temperature / RPM, Start/Stop, and preset switching.
- Settings: launch at login, monitor on launch, resume fan control on launch,
  menu bar visibility, and notifications when control stops on its own.
- Temperature and fan RPM history charts (last 10 minutes).
- Preset export and import as JSON.

- Control all fans at once, each clamped to its own hardware RPM range.
- Combine several temperature sensors (hottest or average) to drive the curve.

- Sensor read retries: the primary sensor is retried within each cycle, and a
  short outage holds the last fan speed (up to 2 cycles / 30 s) with a warning
  instead of stopping control right away.

### Changed
- Loading a preset while fan control is running applies it immediately.
- Helper 2.1: `setMode` takes a `fanMask`, and restoring automatic mode always
  covers every fan. The app now requires helper 2.1, so existing installs show
  "Update Fan Control Helper" once.

### Fixed
- Manual mode previously switched only fan 0, so selecting another fan index
  wrote targets to a fan that stayed in automatic mode.

### Removed
- Stray build output, editor backups, per-user Xcode state, and an outdated
  duplicate Korean README from version control.
