//
//  AppRuntime.swift
//  SMCController
//

import Foundation

enum AppRuntime {
    /// True when XCTest launched this process as the unit-test host. The app then skips
    /// hardware access, helper checks and launch actions: tests use fakes, and on CI
    /// machines those calls can stall the main thread before the test runner connects.
    nonisolated static let isRunningUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
