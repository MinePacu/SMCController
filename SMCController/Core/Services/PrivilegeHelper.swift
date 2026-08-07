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
    private(set) var availability: HelperAvailability = .notInstalled

    private init() {}

    static func isRunningAsRoot() -> Bool {
        geteuid() == 0
    }

    func refreshStatus() async {
        helperInstalled = DaemonClient.shared.isHelperInstalled
        availability = await DaemonClient.shared.helperAvailability()
        daemonRunning = availability.isReady
        hasPrivileges = availability.isReady
        statusMessage = availability.statusMessage
    }

    @discardableResult
    func requestPrivilegesAndRelaunch() async -> Bool {
        // This path is only called by the explicit setup button. Refreshes and normal
        // feature calls never cause an authorization prompt.
        let installed = await DaemonClient.shared.installHelperFromBundle()
        await refreshStatus()
        return installed && hasPrivileges
    }
}
