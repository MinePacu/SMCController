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
                interval: TimeInterval = 5.0) {
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
        self.interval = max(5.0, interval)
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
            interval: container.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 5.0
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
    func startInternal(settings: UserFanSettings, sharedSMC: SMCService? = nil) async throws {
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

        var fanIndex = settings.fanIndex
        if let count = await MainActor.run(body: { try? smc.fanCount() }), count > 0 {
            fanIndex = min(max(0, fanIndex), count - 1)
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
        let policy = FanPolicy(config: cfg, usePID: settings.usePID)
        let loopCfg = FanControllerConfig(sensorKey: settings.sensorKey,
                                          fanIndex: fanIndex,
                                          interval: settings.interval)
        let controller = FanController(smc: smc, policy: policy, config: loopCfg)
        self.controller = controller
        try await controller.start()
    }

    public func update(settings: UserFanSettings) async {
        guard let controller else { return }

        var fanIndex = settings.fanIndex
        if let smc = smc,
           let count = await MainActor.run(body: { try? smc.fanCount() }),
           count > 0 {
            fanIndex = min(max(0, fanIndex), count - 1)
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
        await controller.updateConfig(FanControllerConfig(sensorKey: settings.sensorKey, fanIndex: fanIndex, interval: settings.interval))
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
