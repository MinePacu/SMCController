//
//  PrivilegeHelper.swift
//  SMCController
//

import Foundation
import Observation

@MainActor
@Observable
final class PrivilegeHelper {
    static let shared = PrivilegeHelper()

    private(set) var hasPrivileges = false
    private(set) var helperInstalled = false
    private(set) var daemonRunning = false
    private(set) var statusMessage: String?

    private init() {
        refreshStatus()
    }

    static func isRunningAsRoot() -> Bool {
        geteuid() == 0
    }

    func refreshStatus() {
        helperInstalled = DaemonClient.shared.isHelperInstalled
        daemonRunning = DaemonClient.shared.isAvailableWithoutPrompt
        hasPrivileges = daemonRunning

        if daemonRunning {
            statusMessage = L10n.string("privileges.helper.installed.running")
        } else if helperInstalled {
            statusMessage = L10n.string("privileges.helper.installed.notResponding")
        } else {
            statusMessage = L10n.string("privileges.helper.notInstalled")
        }
    }

    @discardableResult
    func requestPrivilegesAndRelaunch() -> Bool {
        let started = DaemonClient.shared.startDaemon()
        refreshStatus()
        return started
    }
}
