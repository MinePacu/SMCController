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

### Changed
- Loading a preset while fan control is running applies it immediately.

### Removed
- Stray build output, editor backups, per-user Xcode state, and an outdated
  duplicate Korean README from version control.
