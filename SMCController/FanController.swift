//
//  FanController.swift
//  SMCController
//
//  Periodic control loop applying FanPolicy to SMC
//

import Foundation

struct FanControllerConfig: Sendable {
    var sensorKey: String = "Tc0P"    // CPU Proximity (기기마다 다를 수 있음)
    var fanIndex: Int = 0             // 제어할 팬 인덱스 (0부터)
    var interval: TimeInterval = 1.0  // 제어 주기(초)
}

actor FanController {
    private let smc: SMCService
    private var policy: FanPolicy
    private var pid = PIDController()
    private var config: FanControllerConfig
    private var task: Task<Void, Never>?
    private var isRunning = false
    private var overrideMismatchCount = 0
    private let overrideToleranceRPM = 200

    init(smc: SMCService, policy: FanPolicy, config: FanControllerConfig) {
        self.smc = smc
        self.policy = policy
        self.config = config
    }

    func updatePolicy(_ policy: FanPolicy) {
        self.policy = policy
        Task { await pid.reset() }
    }

    func updateConfig(_ config: FanControllerConfig) {
        self.config = config
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        // Ensure manual mode and clamp RPM bounds; if hardware read fails, fall back to user config
        let fanMin = (try? smc.minRPM(fan: config.fanIndex)) ?? policy.config.minRPM
        let fanMax = (try? smc.maxRPM(fan: config.fanIndex)) ?? policy.config.maxRPM
        // Merge hardware bounds with policy bounds
        var cfg = policy.config
        cfg.minRPM = max(cfg.minRPM, fanMin)
        cfg.maxRPM = min(cfg.maxRPM, fanMax)
        policy = FanPolicy(config: cfg, usePID: policy.usePID)

        // Best effort: some machines (esp. newer/managed/AS) reject FS! manual mode writes.
        do {
            try await smc.setManualMode(true)
        } catch {
            print("SMC manual mode not supported (continuing best-effort): \(error)")
        }

        task = Task.detached { [weak self] in
            guard let self else { return }
            await self.loop()
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        isRunning = false
        // Best-effort: return to auto mode (ignore errors)
        do {
            try await smc.setManualMode(false)
        } catch {
            print("[FanController] ⚠️ Failed to disable manual mode on stop (ignoring): \(error)")
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            do {
                let temp = try smc.readTemperatureC(key: config.sensorKey)
                var rpm = policy.rpm(for: temp)

                if policy.usePID {
                    let error = temp - policy.config.targetC
                    let pidAdjust = await pid.step(error: error, kp: policy.config.kp, ki: policy.config.ki, kd: policy.config.kd)
                    rpm = Int(round(Double(rpm) + pidAdjust))
                }

                rpm = policy.clamped(rpm)

                try await smc.setTargetRPM(fan: config.fanIndex, rpm: rpm)

                // Read-back verification to detect override/OS reclaiming control.
                if let actual = try? smc.currentRPM(fan: config.fanIndex) {
                    if abs(actual - rpm) > overrideToleranceRPM {
                        overrideMismatchCount += 1
                        if overrideMismatchCount >= 3 {
                            print("Fan override detected: target \(rpm) vs actual \(actual)")
                        }
                    } else {
                        overrideMismatchCount = max(0, overrideMismatchCount - 1)
                    }
                }
            } catch {
                // On error, attempt to break the loop after small delay
                // Consider logging
            }

            try? await Task.sleep(nanoseconds: UInt64(config.interval * 1_000_000_000))
        }
    }
}
