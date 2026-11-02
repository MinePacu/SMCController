//
//  FanController.swift
//  SMCController
//
//  Periodic control loop applying FanPolicy to SMC.
//

import Foundation

/// Timing is normalized at every boundary which accepts user-provided settings.
/// Keeping the policy here prevents the loop and the helper lease from drifting apart.
enum FanControlTiming {
    nonisolated static let allowedInterval: ClosedRange<TimeInterval> = 5...20
    nonisolated static let allowedWatchdogSeconds: ClosedRange<Int> = 15...60

    nonisolated static func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return allowedInterval.lowerBound }
        return min(max(interval, allowedInterval.lowerBound), allowedInterval.upperBound)
    }

    nonisolated static func watchdogSeconds(for interval: TimeInterval) -> Int {
        let normalized = normalizedInterval(interval)
        return min(
            max(Int((normalized * 3).rounded()), allowedWatchdogSeconds.lowerBound),
            allowedWatchdogSeconds.upperBound
        )
    }
}

struct FanControllerConfig: Sendable {
    var sensorKey: String
    var fanIndex: Int
    var interval: TimeInterval
    /// Manual control stops and the system takes over at or above this temperature.
    var criticalTempC: Double

    nonisolated init(
        sensorKey: String = "Tc0P",
        fanIndex: Int = 0,
        interval: TimeInterval = 5.0,
        criticalTempC: Double = FanSafetyLimits.defaultCriticalTempC
    ) {
        self.sensorKey = sensorKey
        self.fanIndex = fanIndex
        self.interval = FanControlTiming.normalizedInterval(interval)
        self.criticalTempC = FanSafetyLimits.normalizedCriticalTemp(criticalTempC)
    }

    /// Returns a copy with every field passed through its normalizer again.
    nonisolated func normalized() -> FanControllerConfig {
        FanControllerConfig(
            sensorKey: sensorKey,
            fanIndex: fanIndex,
            interval: interval,
            criticalTempC: criticalTempC
        )
    }
}

enum FanControlFailureKind: Sendable, Equatable {
    case sensorRead
    case overheat
    case calculation
    case rpmWrite
}

enum FanControlRestoration: Sendable, Equatable {
    case restored
    case watchdogPending
}

struct FanControlFailure: Sendable, Equatable {
    let kind: FanControlFailureKind
    let message: String
    let restoration: FanControlRestoration
}

/// The control loop depends on this narrow seam rather than a concrete SMC connection.
/// Hardware reads remain on the main actor; root helper writes remain asynchronous.
struct FanControllerIO {
    let readTemperature: @MainActor (String) throws -> Double
    let readMinRPM: @MainActor (Int) throws -> Int
    let readMaxRPM: @MainActor (Int) throws -> Int
    let readCurrentRPM: @MainActor (Int) throws -> Int
    let setTargetRPM: (Int, Int) async throws -> Void
    let setManualMode: (Bool, Int?) async throws -> Void

    @MainActor
    init(smc: SMCService) {
        readTemperature = { try smc.readTemperatureC(key: $0) }
        readMinRPM = { try smc.minRPM(fan: $0) }
        readMaxRPM = { try smc.maxRPM(fan: $0) }
        readCurrentRPM = { try smc.currentRPM(fan: $0) }
        setTargetRPM = { fan, rpm in try await smc.setTargetRPM(fan: fan, rpm: rpm) }
        setManualMode = { enabled, watchdogSeconds in
            try await smc.setManualMode(enabled, watchdogSeconds: watchdogSeconds)
        }
    }

    init(
        readTemperature: @escaping @MainActor (String) throws -> Double,
        readMinRPM: @escaping @MainActor (Int) throws -> Int,
        readMaxRPM: @escaping @MainActor (Int) throws -> Int,
        readCurrentRPM: @escaping @MainActor (Int) throws -> Int,
        setTargetRPM: @escaping (Int, Int) async throws -> Void,
        setManualMode: @escaping (Bool, Int?) async throws -> Void
    ) {
        self.readTemperature = readTemperature
        self.readMinRPM = readMinRPM
        self.readMaxRPM = readMaxRPM
        self.readCurrentRPM = readCurrentRPM
        self.setTargetRPM = setTargetRPM
        self.setManualMode = setManualMode
    }
}

actor FanController {
    private enum State: Equatable {
        case idle
        case starting
        case running
        case stopping
        case failed
    }

    private let io: FanControllerIO
    private let onFailure: (@MainActor (FanControlFailure) -> Void)?
    private var policy: FanPolicy
    private var pid = PIDController()
    private var smoother = FanOutputSmoother()
    private var lastStepTime: Date?
    private var config: FanControllerConfig
    private var task: Task<Void, Never>?
    private var state: State = .idle
    private var sessionID = UUID()
    private var manualModeEnabled = false
    private var autoRestoreAttempted = false
    private var lastRestoration: FanControlRestoration = .restored
    private var overrideMismatchCount = 0
    private let overrideToleranceRPM = 200

    init(
        io: FanControllerIO,
        policy: FanPolicy,
        config: FanControllerConfig,
        onFailure: (@MainActor (FanControlFailure) -> Void)? = nil
    ) {
        self.io = io
        self.policy = policy
        self.config = config
        self.onFailure = onFailure
    }

    func updatePolicy(_ policy: FanPolicy) async {
        self.policy = policy
        await pid.reset()
    }

    @discardableResult
    func updateConfig(_ config: FanControllerConfig) async -> Bool {
        let normalizedConfig = config.normalized()

        guard state == .running else {
            self.config = normalizedConfig
            return true
        }

        // A longer interval needs a longer lease before it becomes active. Re-arm first so
        // the helper can never expire in the gap between the old and new polling cadences.
        do {
            try await io.setManualMode(
                true,
                FanControlTiming.watchdogSeconds(for: normalizedConfig.interval)
            )
        } catch {
            let session = sessionID
            await fail(.rpmWrite, error: error, session: session)
            return false
        }

        guard state == .running else { return false }
        self.config = normalizedConfig
        return true
    }

    func start() async throws {
        guard state == .idle else { return }

        state = .starting
        task?.cancel()
        task = nil
        sessionID = UUID()
        autoRestoreAttempted = false
        lastRestoration = .restored
        overrideMismatchCount = 0
        smoother.reset()
        lastStepTime = nil
        config = config.normalized()

        // Keep UI policy inside the physical range when the read succeeds. The root helper
        // still independently validates every write, so a failed advisory read cannot widen it.
        let fanIndex = config.fanIndex
        let fallbackMinRPM = policy.config.minRPM
        let fallbackMaxRPM = policy.config.maxRPM
        let fanMin = (try? await io.readMinRPM(fanIndex)) ?? fallbackMinRPM
        let fanMax = (try? await io.readMaxRPM(fanIndex)) ?? fallbackMaxRPM
        let mergedMin = max(policy.config.minRPM, fanMin)
        let mergedMax = min(policy.config.maxRPM, fanMax)
        if mergedMin <= mergedMax {
            var updatedConfig = policy.config
            updatedConfig.minRPM = mergedMin
            updatedConfig.maxRPM = mergedMax
            policy = FanPolicy(config: updatedConfig, usePID: policy.usePID)
        }

        let watchdogSeconds = FanControlTiming.watchdogSeconds(for: config.interval)
        do {
            try await io.setManualMode(true, watchdogSeconds)
        } catch {
            state = .idle
            throw error
        }
        manualModeEnabled = true

        // Stop can race while the XPC call is suspended. In that case start owns the
        // compensating automatic-mode request and must not create a control task.
        guard state == .starting else {
            _ = await restoreAutomaticModeOnce()
            state = .idle
            return
        }

        state = .running
        let session = sessionID
        task = Task { [weak self] in
            await self?.loop(session: session)
        }
    }

    func stop() async {
        switch state {
        case .idle, .failed, .stopping:
            return
        case .starting:
            // `start` will observe this state after enabling manual mode and restore once.
            state = .stopping
            return
        case .running:
            state = .stopping
            task?.cancel()
            task = nil
            _ = await restoreAutomaticModeOnce()
            if state == .stopping {
                state = .idle
            }
        }
    }

    private func loop(session: UUID) async {
        while !Task.isCancelled {
            guard isActive(session: session) else { return }

            let sensorKey = config.sensorKey
            let fanIndex = config.fanIndex
            let temperature: Double
            do {
                temperature = try await io.readTemperature(sensorKey)
                // A stuck-at-zero or wildly high value means the sensor cannot be trusted
                // to drive the fan, so treat it the same as a failed read.
                guard FanSafetyLimits.isPlausible(temperature) else {
                    throw SafetyError.implausibleTemperature(sensorKey, temperature)
                }
            } catch is CancellationError {
                return
            } catch {
                await fail(.sensorRead, error: error, session: session)
                return
            }

            guard isActive(session: session) else { return }

            // Past the critical temperature, the system thermal policy is safer than any
            // user curve: hand control back instead of trying to out-cool it.
            if temperature >= config.criticalTempC {
                await fail(
                    .overheat,
                    error: SafetyError.overheat(temperature, config.criticalTempC),
                    session: session
                )
                return
            }

            let rpm: Int
            do {
                var calculated = policy.rpm(for: temperature)
                if policy.usePID {
                    let error = temperature - policy.config.targetC
                    let adjustment = await pid.step(
                        error: error,
                        kp: policy.config.kp,
                        ki: policy.config.ki,
                        kd: policy.config.kd
                    )
                    let adjusted = Double(calculated) + adjustment
                    guard adjusted.isFinite,
                          adjusted >= Double(Int.min),
                          adjusted <= Double(Int.max) else {
                        throw CalculationError.nonFiniteOutput
                    }
                    calculated = Int(adjusted.rounded())
                }
                let now = Date()
                let elapsed = lastStepTime.map { now.timeIntervalSince($0) } ?? config.interval
                lastStepTime = now
                // PID already reacts to the trend; a hysteresis dead band would only
                // fight its integral term. Keep the ramp-down limit in both modes.
                smoother.hysteresisC = policy.usePID ? 0 : 2
                let target = policy.clamped(calculated)
                rpm = policy.clamped(
                    smoother.next(target: target, temperatureC: temperature, elapsed: elapsed)
                )
            } catch {
                await fail(.calculation, error: error, session: session)
                return
            }

            guard isActive(session: session) else { return }

            do {
                try await io.setTargetRPM(fanIndex, rpm)
            } catch is CancellationError {
                return
            } catch {
                await fail(.rpmWrite, error: error, session: session)
                return
            }

            guard isActive(session: session) else { return }
            if let actual = try? await io.readCurrentRPM(fanIndex) {
                if abs(actual - rpm) > overrideToleranceRPM {
                    overrideMismatchCount += 1
                    if overrideMismatchCount >= 3 {
                        print("Fan override detected: target \(rpm) vs actual \(actual)")
                    }
                } else {
                    overrideMismatchCount = max(0, overrideMismatchCount - 1)
                }
            }

            do {
                let nanoseconds = UInt64(config.interval * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func isActive(session: UUID) -> Bool {
        state == .running && sessionID == session && !Task.isCancelled
    }

    private func fail(_ kind: FanControlFailureKind, error: Error, session: UUID) async {
        guard isActive(session: session) else { return }

        state = .failed
        task?.cancel()
        task = nil
        let restoration = await restoreAutomaticModeOnce()
        let failure = FanControlFailure(
            kind: kind,
            message: error.localizedDescription,
            restoration: restoration
        )
        if let onFailure {
            await onFailure(failure)
        }
    }

    private func restoreAutomaticModeOnce() async -> FanControlRestoration {
        guard manualModeEnabled else { return lastRestoration }
        guard !autoRestoreAttempted else { return lastRestoration }

        autoRestoreAttempted = true
        do {
            try await io.setManualMode(false, nil)
            manualModeEnabled = false
            lastRestoration = .restored
        } catch {
            // A running helper owns the lease and will keep retrying its own watchdog recovery.
            lastRestoration = .watchdogPending
        }
        return lastRestoration
    }

    private enum SafetyError: LocalizedError {
        case implausibleTemperature(String, Double)
        case overheat(Double, Double)

        var errorDescription: String? {
            switch self {
            case let .implausibleTemperature(key, value):
                return "Sensor \(key) reported an implausible temperature (\(String(format: "%.1f", value)) °C)."
            case let .overheat(value, limit):
                return "Temperature \(String(format: "%.1f", value)) °C reached the critical limit of \(Int(limit)) °C."
            }
        }
    }

    private enum CalculationError: LocalizedError {
        case nonFiniteOutput

        var errorDescription: String? {
            "The fan control calculation produced an invalid RPM."
        }
    }
}
