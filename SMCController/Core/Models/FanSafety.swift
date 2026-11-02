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

/// How the control loop rides out a flaky primary sensor.
///
/// Each cycle retries a failed or implausible primary reading a few times. If the
/// cycle still has no reading, the last fan speed is held for a short outage; past
/// that, control stops and the fans go back to automatic mode. Nothing is held
/// before the first good reading, because there is no known-good speed yet.
struct SensorRetryPolicy: Sendable {
    var attemptsPerCycle: Int
    var retryDelay: TimeInterval
    var maxConsecutiveFailedCycles: Int
    var maxOutage: TimeInterval

    nonisolated init(
        attemptsPerCycle: Int = 3,
        retryDelay: TimeInterval = 0.25,
        maxConsecutiveFailedCycles: Int = 2,
        maxOutage: TimeInterval = 30
    ) {
        self.attemptsPerCycle = max(1, attemptsPerCycle)
        self.retryDelay = retryDelay.isFinite ? max(0, retryDelay) : 0
        self.maxConsecutiveFailedCycles = max(0, maxConsecutiveFailedCycles)
        self.maxOutage = maxOutage.isFinite ? max(0, maxOutage) : 0
    }

    nonisolated static let standard = SensorRetryPolicy()

    /// Whether a cycle without a reading may keep the last speed instead of stopping.
    nonisolated func allowsHolding(consecutiveFailedCycles: Int, lastGoodReading: Date?, now: Date) -> Bool {
        guard let lastGoodReading else { return false }
        return consecutiveFailedCycles <= maxConsecutiveFailedCycles
            && now.timeIntervalSince(lastGoodReading) <= maxOutage
    }
}

/// Reported while the loop is holding speed because of a sensor problem.
nonisolated enum SensorReadStatus: Sendable, Equatable {
    case degraded(key: String, message: String)
    case recovered
}
