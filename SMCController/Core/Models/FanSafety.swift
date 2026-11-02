//
//  FanSafety.swift
//  SMCController
//
//  Safety limits and output smoothing applied on top of FanPolicy.
//

import Foundation

/// Limits that make the control loop hand fans back to the system.
enum FanSafetyLimits {
    /// Default temperature at which manual control gives up and macOS takes over.
    nonisolated static let defaultCriticalTempC: Double = 100
    /// Range a user may choose for the critical temperature.
    nonisolated static let allowedCriticalTempC: ClosedRange<Double> = 70...110
    /// Readings outside this range are treated as a broken or missing sensor.
    nonisolated static let plausibleTempC: ClosedRange<Double> = 1...150

    nonisolated static func normalizedCriticalTemp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultCriticalTempC }
        return min(max(value, allowedCriticalTempC.lowerBound), allowedCriticalTempC.upperBound)
    }

    nonisolated static func isPlausible(_ temperatureC: Double) -> Bool {
        temperatureC.isFinite && plausibleTempC.contains(temperatureC)
    }
}

/// Keeps fan speed from bouncing when the temperature hovers around a curve point.
///
/// - Increases are applied immediately, so cooling is never delayed.
/// - Decreases wait until the temperature has dropped `hysteresisC` below the
///   temperature that set the current speed, then step down at most
///   `rampDownRPMPerSecond`.
struct FanOutputSmoother: Sendable {
    var hysteresisC: Double
    var rampDownRPMPerSecond: Double

    private var lastRPM: Int?
    private var anchorTempC: Double?

    nonisolated init(hysteresisC: Double = 2, rampDownRPMPerSecond: Double = 100) {
        self.hysteresisC = max(0, hysteresisC)
        self.rampDownRPMPerSecond = max(1, rampDownRPMPerSecond)
    }

    nonisolated mutating func reset() {
        lastRPM = nil
        anchorTempC = nil
    }

    nonisolated mutating func next(target: Int, temperatureC: Double, elapsed: TimeInterval) -> Int {
        guard let last = lastRPM, let anchor = anchorTempC else {
            lastRPM = target
            anchorTempC = temperatureC
            return target
        }

        if target >= last {
            lastRPM = target
            anchorTempC = temperatureC
            return target
        }

        // Still inside the hysteresis band: hold the current speed.
        if temperatureC > anchor - hysteresisC {
            return last
        }

        let seconds = elapsed.isFinite ? max(0, elapsed) : 0
        let maxStep = max(1, Int((rampDownRPMPerSecond * seconds).rounded()))
        let next = max(target, last - maxStep)
        lastRPM = next
        return next
    }
}
