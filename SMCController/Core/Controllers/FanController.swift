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
    /// Primary sensor. It must always be readable; control stops if it is not.
    var sensorKey: String
    /// Extra sensors combined with the primary one when `aggregation` is not `.primary`.
    var additionalSensorKeys: [String]
    var aggregation: SensorAggregation
    /// Fans that receive the curve output. Never empty.
    var fanIndices: [Int]
    var interval: TimeInterval
    /// Manual control stops and the system takes over at or above this temperature.
    var criticalTempC: Double

    nonisolated init(
        sensorKey: String = "Tc0P",
        fanIndex: Int = 0,
        fanIndices: [Int]? = nil,
        interval: TimeInterval = 5.0,
        criticalTempC: Double = FanSafetyLimits.defaultCriticalTempC,
        additionalSensorKeys: [String] = [],
        aggregation: SensorAggregation = .primary
    ) {
        self.sensorKey = sensorKey
        self.additionalSensorKeys = SensorKeyList.unique(additionalSensorKeys.filter { $0 != sensorKey })
        self.aggregation = aggregation
        self.fanIndices = FanSelection.normalized(fanIndices ?? [fanIndex])
        self.interval = FanControlTiming.normalizedInterval(interval)
        self.criticalTempC = FanSafetyLimits.normalizedCriticalTemp(criticalTempC)
    }

    /// The first controlled fan; kept for callers that only show one fan.
    nonisolated var fanIndex: Int { fanIndices.first ?? 0 }

    nonisolated var fanMask: Int { FanSelection.mask(for: fanIndices) }

    /// Sensors read every cycle. The primary sensor is always first.
    nonisolated var controlSensorKeys: [String] {
        aggregation == .primary ? [sensorKey] : [sensorKey] + additionalSensorKeys
    }

    /// Returns a copy with every field passed through its normalizer again.
    nonisolated func normalized() -> FanControllerConfig {
        FanControllerConfig(
            sensorKey: sensorKey,
            fanIndices: fanIndices,
            interval: interval,
            criticalTempC: criticalTempC,
            additionalSensorKeys: additionalSensorKeys,
            aggregation: aggregation
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
    /// (enabled, watchdog seconds, fan mask). The mask is ignored when disabling,
    /// which always returns every fan to automatic mode.
    let setManualMode: (Bool, Int?, Int) async throws -> Void

    @MainActor
    init(smc: SMCService) {
        readTemperature = { try smc.readTemperatureC(key: $0) }
        readMinRPM = { try smc.minRPM(fan: $0) }
        readMaxRPM = { try smc.maxRPM(fan: $0) }
        readCurrentRPM = { try smc.currentRPM(fan: $0) }
        setTargetRPM = { fan, rpm in try await smc.setTargetRPM(fan: fan, rpm: rpm) }
        setManualMode = { enabled, watchdogSeconds, fanMask in
            try await smc.setManualMode(enabled, watchdogSeconds: watchdogSeconds, fanMask: fanMask)
        }
    }

    init(
        readTemperature: @escaping @MainActor (String) throws -> Double,
        readMinRPM: @escaping @MainActor (Int) throws -> Int,
        readMaxRPM: @escaping @MainActor (Int) throws -> Int,
        readCurrentRPM: @escaping @MainActor (Int) throws -> Int,
        setTargetRPM: @escaping (Int, Int) async throws -> Void,
        setManualMode: @escaping (Bool, Int?, Int) async throws -> Void
    ) {
        self.readTemperature = readTemperature
        self.readMinRPM = readMinRPM
        self.readMaxRPM = readMaxRPM
        self.readCurrentRPM = readCurrentRPM
        self.setTargetRPM = setTargetRPM
        self.setManualMode = setManualMode
    }
}

/// Clamps one shared curve output into each fan's own range.
enum FanRangeResolver {
    /// Intersects the policy range with the fan's hardware range. If they do not overlap,
    /// the hardware range wins because the helper rejects anything outside it anyway.
    nonisolated static func range(
        policyMin: Int,
        policyMax: Int,
        hardwareMin: Int?,
        hardwareMax: Int?
    ) -> ClosedRange<Int> {
        let policyRange = min(policyMin, policyMax)...max(policyMin, policyMax)
        guard let hardwareMin, let hardwareMax, hardwareMin <= hardwareMax else {
            return policyRange
        }
        let low = max(policyRange.lowerBound, hardwareMin)
        let high = min(policyRange.upperBound, hardwareMax)
        return low <= high ? low...high : hardwareMin...hardwareMax
    }

    nonisolated static func clamp(_ rpm: Int, to range: ClosedRange<Int>) -> Int {
        min(max(rpm, range.lowerBound), range.upperBound)
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

    private struct HardwareLimits {
        let minRPM: Int?
        let maxRPM: Int?
    }

    private let io: FanControllerIO
    private let onFailure: (@MainActor (FanControlFailure) -> Void)?
    private var policy: FanPolicy
    private var pid = PIDController()
    private var smoother = FanOutputSmoother()
    private var lastStepTime: Date?
    private var config: FanControllerConfig
    private var hardwareLimits: [Int: HardwareLimits] = [:]
    private var task: Task<Void, Never>?
    private var state: State = .idle
    private var sessionID = UUID()
    private var manualModeEnabled = false
    private var autoRestoreAttempted = false
    private var lastRestoration: FanControlRestoration = .restored
    private var overrideMismatchCount: [Int: Int] = [:]
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

        // A longer interval needs a longer lease before it becomes active, and a new fan
        // set must be in manual mode before it is written. Re-arm first so the helper can
        // never expire in the gap between the old and new polling cadences.
        do {
            try await io.setManualMode(
                true,
                FanControlTiming.watchdogSeconds(for: normalizedConfig.interval),
                normalizedConfig.fanMask
            )
        } catch {
            let session = sessionID
            await fail(.rpmWrite, error: error, session: session)
            return false
        }

        guard state == .running else { return false }
        await loadHardwareLimits(for: normalizedConfig.fanIndices)
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
        overrideMismatchCount = [:]
        smoother.reset()
        lastStepTime = nil
        hardwareLimits = [:]
        config = config.normalized()

        // Keep output inside each fan's physical range when the read succeeds. The root
        // helper still independently validates every write, so a failed advisory read
        // cannot widen it.
        await loadHardwareLimits(for: config.fanIndices)

        let watchdogSeconds = FanControlTiming.watchdogSeconds(for: config.interval)
        do {
            try await io.setManualMode(true, watchdogSeconds, config.fanMask)
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

    private func loadHardwareLimits(for fans: [Int]) async {
        for fan in fans where hardwareLimits[fan] == nil {
            let minRPM = try? await io.readMinRPM(fan)
            let maxRPM = try? await io.readMaxRPM(fan)
            hardwareLimits[fan] = HardwareLimits(minRPM: minRPM, maxRPM: maxRPM)
        }
    }

    private func range(for fan: Int) -> ClosedRange<Int> {
        let limits = hardwareLimits[fan]
        return FanRangeResolver.range(
            policyMin: policy.config.minRPM,
            policyMax: policy.config.maxRPM,
            hardwareMin: limits?.minRPM,
            hardwareMax: limits?.maxRPM
        )
    }

    /// Reads every control sensor. The primary sensor must be valid; an extra sensor
    /// that fails or reports nonsense is skipped for this cycle.
    private func readTemperatures(_ keys: [String]) async throws -> [Double] {
        var values: [Double] = []
        for (offset, key) in keys.enumerated() {
            do {
                let value = try await io.readTemperature(key)
                // A stuck-at-zero or wildly high value means the sensor cannot be trusted
                // to drive the fan, so treat it the same as a failed read.
                guard FanSafetyLimits.isPlausible(value) else {
                    throw SafetyError.implausibleTemperature(key, value)
                }
                values.append(value)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if offset == 0 { throw error }
                print("[FanController] Skipping sensor \(key) this cycle: \(error.localizedDescription)")
            }
        }
        return values
    }

    private func loop(session: UUID) async {
        while !Task.isCancelled {
            guard isActive(session: session) else { return }

            let currentConfig = config
            let readings: [Double]
            do {
                readings = try await readTemperatures(currentConfig.controlSensorKeys)
            } catch is CancellationError {
                return
            } catch {
                await fail(.sensorRead, error: error, session: session)
                return
            }

            guard isActive(session: session) else { return }

            // Past the critical temperature, the system thermal policy is safer than any
            // user curve: hand control back instead of trying to out-cool it. This uses
            // the hottest reading even in average mode so averaging can never hide it.
            let hottest = readings.max() ?? 0
            if hottest >= currentConfig.criticalTempC {
                await fail(
                    .overheat,
                    error: SafetyError.overheat(hottest, currentConfig.criticalTempC),
                    session: session
                )
                return
            }

            let temperature = currentConfig.aggregation.combine(readings) ?? hottest

            let target: Int
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
                let elapsed = lastStepTime.map { now.timeIntervalSince($0) } ?? currentConfig.interval
                lastStepTime = now
                // PID already reacts to the trend; a hysteresis dead band would only
                // fight its integral term. Keep the ramp-down limit in both modes.
                smoother.hysteresisC = policy.usePID ? 0 : 2
                target = policy.clamped(
                    smoother.next(
                        target: policy.clamped(calculated),
                        temperatureC: temperature,
                        elapsed: elapsed
                    )
                )
            } catch {
                await fail(.calculation, error: error, session: session)
                return
            }

            for fan in currentConfig.fanIndices {
                guard isActive(session: session) else { return }
                let rpm = FanRangeResolver.clamp(target, to: range(for: fan))
                do {
                    try await io.setTargetRPM(fan, rpm)
                } catch is CancellationError {
                    return
                } catch {
                    await fail(.rpmWrite, error: error, session: session)
                    return
                }

                guard isActive(session: session) else { return }
                let actual = try? await io.readCurrentRPM(fan)
                checkOverride(fan: fan, target: rpm, actual: actual)
            }

            do {
                let nanoseconds = UInt64(currentConfig.interval * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func checkOverride(fan: Int, target: Int, actual: Int?) {
        guard let actual else { return }
        let count = overrideMismatchCount[fan, default: 0]
        if abs(actual - target) > overrideToleranceRPM {
            overrideMismatchCount[fan] = count + 1
            if count + 1 >= 3 {
                print("Fan \(fan) override detected: target \(target) vs actual \(actual)")
            }
        } else {
            overrideMismatchCount[fan] = max(0, count - 1)
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
            try await io.setManualMode(false, nil, 0)
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
