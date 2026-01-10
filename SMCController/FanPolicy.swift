//
//  FanPolicy.swift
//  SMCController
//
//  Temperature -> RPM policy (curve + optional PID)
//

import Foundation

public struct FanCurvePoint: Codable, Sendable, Hashable, Comparable {
    public var tempC: Double
    public var rpm: Int

    public static func < (lhs: FanCurvePoint, rhs: FanCurvePoint) -> Bool {
        lhs.tempC < rhs.tempC
    }
}

struct FanPolicyConfig: Sendable {
    // 커브가 우선 사용됩니다. 비어 있으면 min/max 선형을 fallback.
    var curve: [FanCurvePoint] = []

    // fallback 및 안전 범위
    var minC: Double              // 이 온도 이하는 최소 RPM
    var maxC: Double              // 이 온도 이상은 최대 RPM
    var minRPM: Int               // 하드 제한 최소
    var maxRPM: Int               // 하드 제한 최대

    // PID (optional) – 커브 결과에 가감
    var targetC: Double           // PID 기준 온도(선택적)
    var kp: Double = 0.0
    var ki: Double = 0.0
    var kd: Double = 0.0
}

actor PIDController {
    private var integral: Double = 0
    private var lastError: Double = 0
    private var lastTime: Date?

    func reset() {
        integral = 0
        lastError = 0
        lastTime = nil
    }

    func step(error: Double, kp: Double, ki: Double, kd: Double) -> Double {
        let now = Date()
        let dt: Double
        if let lt = lastTime {
            dt = max(1e-3, now.timeIntervalSince(lt))
        } else {
            dt = 0.1
        }
        integral += error * dt
        let derivative = (error - lastError) / dt
        lastError = error
        lastTime = now
        return kp * error + ki * integral + kd * derivative
    }
}

struct FanPolicy {
    var config: FanPolicyConfig
    var usePID: Bool

    // 커브를 이용한 RPM 계산
    func rpm(for temperatureC: Double) -> Int {
        let rpmFromCurve = rpmFromCurveOrLinear(for: temperatureC)
        return clamped(rpmFromCurve)
    }

    func clamped(_ rpm: Int) -> Int {
        return max(config.minRPM, min(config.maxRPM, rpm))
    }

    private func rpmFromCurveOrLinear(for t: Double) -> Int {
        let curve = config.curve.sorted()
        if curve.count >= 2 {
            // 범위 밖은 양 끝 값으로 클램프
            if t <= curve.first!.tempC { return curve.first!.rpm }
            if t >= curve.last!.tempC  { return curve.last!.rpm }
            // 구간 선형 보간
            for i in 0..<(curve.count - 1) {
                let a = curve[i], b = curve[i+1]
                if t >= a.tempC && t <= b.tempC {
                    let ratio = (t - a.tempC) / (b.tempC - a.tempC)
                    let v = Double(a.rpm) + ratio * Double(b.rpm - a.rpm)
                    return Int(round(v))
                }
            }
        }
        // 커브가 없으면 min/max 선형
        let minC = config.minC
        let maxC = config.maxC
        let minR = Double(config.minRPM)
        let maxR = Double(config.maxRPM)

        if t <= minC { return Int(minR) }
        if t >= maxC { return Int(maxR) }
        let ratio = (t - minC) / (maxC - minC)
        return Int(round(minR + ratio * (maxR - minR)))
    }
}
