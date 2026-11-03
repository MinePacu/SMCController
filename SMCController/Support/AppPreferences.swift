//
//  AppPreferences.swift
//  SMCController
//
//  App-wide behavior settings shown in the macOS Settings window.
//

import Foundation
import Observation
import ServiceManagement

@Observable
final class AppPreferences {
    enum Key {
        static let showMenuBarExtra = "com.minepacu.smccontroller.showMenuBarExtra"
        static let monitorOnLaunch = "com.minepacu.smccontroller.monitorOnLaunch"
        static let resumeControlOnLaunch = "com.minepacu.smccontroller.resumeControlOnLaunch"
        static let notifyOnControlStop = "com.minepacu.smccontroller.notifyOnControlStop"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Shows temperature and fan speed in the menu bar.
    var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: Key.showMenuBarExtra) }
    }

    /// Starts read-only monitoring when the app launches.
    var monitorOnLaunch: Bool {
        didSet { defaults.set(monitorOnLaunch, forKey: Key.monitorOnLaunch) }
    }

    /// Starts fan control with the last settings when the app launches.
    /// Only takes effect when the helper is already installed; it never prompts.
    var resumeControlOnLaunch: Bool {
        didSet { defaults.set(resumeControlOnLaunch, forKey: Key.resumeControlOnLaunch) }
    }

    /// Posts a notification when fan control stops on its own (overheat, sensor or write failure).
    var notifyOnControlStop: Bool {
        didSet { defaults.set(notifyOnControlStop, forKey: Key.notifyOnControlStop) }
    }

    /// Mirrors the system login item state; macOS is the source of truth.
    private(set) var launchAtLogin: Bool = false
    private(set) var launchAtLoginNeedsApproval: Bool = false
    var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showMenuBarExtra = defaults.object(forKey: Key.showMenuBarExtra) as? Bool ?? true
        monitorOnLaunch = defaults.object(forKey: Key.monitorOnLaunch) as? Bool ?? true
        resumeControlOnLaunch = defaults.object(forKey: Key.resumeControlOnLaunch) as? Bool ?? false
        notifyOnControlStop = defaults.object(forKey: Key.notifyOnControlStop) as? Bool ?? true
        // Querying login items talks to a system service; the unit-test host skips it.
        if !AppRuntime.isRunningUnitTests {
            refreshLaunchAtLogin()
        }
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = L10n.string("settings.launchAtLogin.error", error.localizedDescription)
        }
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

}
