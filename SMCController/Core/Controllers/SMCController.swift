//
//  SMCController.swift
//  SMCController
//

import Foundation

public struct UserFanSettings: Codable, Sendable {
    public var targetC: Double
    public var minC: Double
    public var maxC: Double
    public var minRPM: Int
    public var maxRPM: Int

    public var curve: [FanCurvePoint]  // 추가: 사용자 커브

    public var usePID: Bool
    public var kp: Double
    public var ki: Double
    public var kd: Double
    public var sensorKey: String
    public var extraSensorKeys: [String]
    public var fanIndex: Int
    public var interval: TimeInterval
    public var criticalTempC: Double
    /// Applies the curve to every detected fan instead of only `fanIndex`.
    public var controlAllFans: Bool
    /// Extra sensors combined with `sensorKey` according to `sensorAggregation`.
    public var controlSensorKeys: [String]
    public var sensorAggregation: SensorAggregation

    private enum CodingKeys: String, CodingKey {
        case targetC
        case minC
        case maxC
        case minRPM
        case maxRPM
        case curve
        case usePID
        case kp
        case ki
        case kd
        case sensorKey
        case extraSensorKeys
        case fanIndex
        case interval
        case criticalTempC
        case controlAllFans
        case controlSensorKeys
        case sensorAggregation
    }

    public init(targetC: Double,
                minC: Double,
                maxC: Double,
                minRPM: Int,
                maxRPM: Int,
                curve: [FanCurvePoint] = [],
                usePID: Bool = false,
                kp: Double = 0, ki: Double = 0, kd: Double = 0,
                sensorKey: String = "Tc0P",
                extraSensorKeys: [String] = [],
                fanIndex: Int = 0,
                interval: TimeInterval = 5.0,
                criticalTempC: Double = FanSafetyLimits.defaultCriticalTempC,
                controlAllFans: Bool = false,
                controlSensorKeys: [String] = [],
                sensorAggregation: SensorAggregation = .primary) {
        self.targetC = targetC
        self.minC = minC
        self.maxC = maxC
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.curve = curve
        self.usePID = usePID
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.sensorKey = sensorKey
        self.extraSensorKeys = extraSensorKeys
        self.fanIndex = fanIndex
        self.interval = FanControlTiming.normalizedInterval(interval)
        self.criticalTempC = FanSafetyLimits.normalizedCriticalTemp(criticalTempC)
        self.controlAllFans = controlAllFans
        self.controlSensorKeys = SensorKeyList.unique(controlSensorKeys)
        self.sensorAggregation = sensorAggregation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            targetC: container.decode(Double.self, forKey: .targetC),
            minC: container.decode(Double.self, forKey: .minC),
            maxC: container.decode(Double.self, forKey: .maxC),
            minRPM: container.decode(Int.self, forKey: .minRPM),
            maxRPM: container.decode(Int.self, forKey: .maxRPM),
            curve: container.decodeIfPresent([FanCurvePoint].self, forKey: .curve) ?? [],
            usePID: container.decodeIfPresent(Bool.self, forKey: .usePID) ?? false,
            kp: container.decodeIfPresent(Double.self, forKey: .kp) ?? 0,
            ki: container.decodeIfPresent(Double.self, forKey: .ki) ?? 0,
            kd: container.decodeIfPresent(Double.self, forKey: .kd) ?? 0,
            sensorKey: container.decodeIfPresent(String.self, forKey: .sensorKey) ?? "Tc0P",
            extraSensorKeys: container.decodeIfPresent([String].self, forKey: .extraSensorKeys) ?? [],
            fanIndex: container.decodeIfPresent(Int.self, forKey: .fanIndex) ?? 0,
            interval: container.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 5.0,
            criticalTempC: container.decodeIfPresent(Double.self, forKey: .criticalTempC)
                ?? FanSafetyLimits.defaultCriticalTempC,
            controlAllFans: container.decodeIfPresent(Bool.self, forKey: .controlAllFans) ?? false,
            controlSensorKeys: container.decodeIfPresent([String].self, forKey: .controlSensorKeys) ?? [],
            // An unknown future mode falls back to the primary sensor rather than failing.
            sensorAggregation: (try? container.decodeIfPresent(SensorAggregation.self, forKey: .sensorAggregation))
                ?? .primary
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetC, forKey: .targetC)
        try container.encode(minC, forKey: .minC)
        try container.encode(maxC, forKey: .maxC)
        try container.encode(minRPM, forKey: .minRPM)
        try container.encode(maxRPM, forKey: .maxRPM)
        try container.encode(curve, forKey: .curve)
        try container.encode(usePID, forKey: .usePID)
        try container.encode(kp, forKey: .kp)
        try container.encode(ki, forKey: .ki)
        try container.encode(kd, forKey: .kd)
        try container.encode(sensorKey, forKey: .sensorKey)
        try container.encode(extraSensorKeys, forKey: .extraSensorKeys)
        try container.encode(fanIndex, forKey: .fanIndex)
        try container.encode(interval, forKey: .interval)
        try container.encode(criticalTempC, forKey: .criticalTempC)
        try container.encode(controlAllFans, forKey: .controlAllFans)
        try container.encode(controlSensorKeys, forKey: .controlSensorKeys)
        try container.encode(sensorAggregation, forKey: .sensorAggregation)
    }
}

public actor SMCControllerAPI {
    private var smc: SMCService?
    private var controller: FanController?
    private var ownsSMC: Bool = false  // Track if we created our own SMC instance

    public init() {}

    // Public API without shared SMC (for external use)
    public func start(settings: UserFanSettings) async throws {
        try await startInternal(settings: settings, sharedSMC: nil)
    }
    
    // Internal API with shared SMC (for ViewModel use)
    func startInternal(
        settings: UserFanSettings,
        sharedSMC: SMCService? = nil,
        onFailure: (@MainActor (FanControlFailure) -> Void)? = nil,
        onSensorStatus: (@MainActor (SensorReadStatus) -> Void)? = nil
    ) async throws {
        // Use shared SMC instance if provided, otherwise create our own
        let smc: SMCService
        if let shared = sharedSMC {
            print("[SMCControllerAPI] Using shared SMC instance")
            smc = shared
            ownsSMC = false
        } else {
            print("[SMCControllerAPI] Creating new SMC instance")
            smc = try await MainActor.run { try SMCService() }
            ownsSMC = true
        }
        self.smc = smc

        let fanCount = await MainActor.run(body: { try? smc.fanCount() })

        let cfg = FanPolicyConfig(
            curve: settings.curve,
            minC: settings.minC,
            maxC: settings.maxC,
            minRPM: settings.minRPM,
            maxRPM: settings.maxRPM,
            targetC: settings.targetC,
            kp: settings.kp, ki: settings.ki, kd: settings.kd
        )
        let policy = FanPolicy(config: cfg, usePID: settings.usePID)
        let loopCfg = Self.controllerConfig(for: settings, fanCount: fanCount)
        let io = await MainActor.run { FanControllerIO(smc: smc) }
        let controller = FanController(
            io: io,
            policy: policy,
            config: loopCfg,
            onFailure: onFailure,
            onSensorStatus: onSensorStatus
        )
        self.controller = controller
        try await controller.start()
    }

    public func update(settings: UserFanSettings) async {
        guard let controller else { return }

        var fanCount: Int?
        if let smc {
            fanCount = await MainActor.run(body: { try? smc.fanCount() })
        }

        let cfg = FanPolicyConfig(
            curve: settings.curve,
            minC: settings.minC,
            maxC: settings.maxC,
            minRPM: settings.minRPM,
            maxRPM: settings.maxRPM,
            targetC: settings.targetC,
            kp: settings.kp, ki: settings.ki, kd: settings.kd
        )
        await controller.updatePolicy(FanPolicy(config: cfg, usePID: settings.usePID))
        await controller.updateConfig(Self.controllerConfig(for: settings, fanCount: fanCount))
    }

    /// Maps user settings to a loop configuration, resolving the fan set against
    /// the detected fan count (nil when it could not be read).
    nonisolated static func controllerConfig(for settings: UserFanSettings, fanCount: Int?) -> FanControllerConfig {
        let usableCount = fanCount.flatMap { $0 > 0 ? $0 : nil }
        return FanControllerConfig(
            sensorKey: settings.sensorKey,
            fanIndices: FanSelection.indices(
                controlAllFans: settings.controlAllFans,
                fanIndex: settings.fanIndex,
                fanCount: usableCount
            ),
            interval: FanControlTiming.normalizedInterval(settings.interval),
            criticalTempC: settings.criticalTempC,
            additionalSensorKeys: settings.controlSensorKeys,
            aggregation: settings.sensorAggregation
        )
    }

    public func stop() async {
        await controller?.stop()
        controller = nil
        
        // Only release SMC if we own it
        if ownsSMC {
            print("[SMCControllerAPI] Releasing owned SMC instance")
            smc = nil
        } else {
            print("[SMCControllerAPI] Keeping shared SMC instance")
        }
        ownsSMC = false
    }
}
