//
//  SMCHelperProxy.swift
//  SMCController
//
//  Compatibility facade for code that previously invoked the helper directly.
//

import Foundation

/// All privileged operations now go through `DaemonClient`'s authenticated XPC transport.
/// This facade intentionally has no process, shell, or socket fallback.
final class SMCHelperProxy {
    static let shared = SMCHelperProxy()

    private(set) var isInstalled = false

    private init() {}

    func checkInstallation() async {
        isInstalled = DaemonClient.shared.isHelperInstalled
    }

    func installHelper() async throws {
        guard await DaemonClient.shared.installHelperFromBundle() else {
            throw DaemonClientError.installation("The helper could not be installed or verified.")
        }
        isInstalled = true
    }

    func setFanRPM(fan: Int, rpm: Int) async throws {
        try await DaemonClient.shared.setFanSpeed(fan: fan, rpm: rpm)
    }

    func setManualMode(enabled: Bool, watchdogSeconds: Int? = nil) async throws {
        try await DaemonClient.shared.setManualMode(
            enabled: enabled,
            watchdogSeconds: watchdogSeconds
        )
    }
}
