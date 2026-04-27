//
//  SMCControllerTests.swift
//  SMCControllerTests
//
//  Created by 노현수 on 11/18/25.
//

import Testing
import Foundation
@testable import SMCController

struct SMCControllerTests {

    @Test func pidFirstStepDoesNotApplyDerivativeKick() async throws {
        let pid = PIDController()

        let output = await pid.step(
            error: 10,
            kp: 2,
            ki: 3,
            kd: 4,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(output == 20)
    }

    @Test func pidSecondStepAppliesIntegralAndDerivativeTerms() async throws {
        let pid = PIDController()

        _ = await pid.step(
            error: 10,
            kp: 2,
            ki: 3,
            kd: 4,
            now: Date(timeIntervalSince1970: 1_000)
        )
        let output = await pid.step(
            error: 14,
            kp: 2,
            ki: 3,
            kd: 4,
            now: Date(timeIntervalSince1970: 1_002)
        )

        #expect(output == 120)
    }

    @Test func userFanSettingsCodableRoundTripPreservesExtraSensorKeys() throws {
        let settings = UserFanSettings(
            targetC: 68,
            minC: 35,
            maxC: 95,
            minRPM: 1300,
            maxRPM: 4200,
            curve: [
                FanCurvePoint(tempC: 45, rpm: 1500),
                FanCurvePoint(tempC: 70, rpm: 2800)
            ],
            usePID: true,
            kp: 12,
            ki: 0.5,
            kd: 1.2,
            sensorKey: "TC0P",
            extraSensorKeys: ["TG0P", "Tp09"],
            fanIndex: 1,
            interval: 6
        )

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserFanSettings.self, from: encoded)

        #expect(decoded.sensorKey == "TC0P")
        #expect(decoded.extraSensorKeys == ["TG0P", "Tp09"])
        #expect(decoded.curve.count == 2)
        #expect(decoded.fanIndex == 1)
        #expect(decoded.interval == 6)
    }

}
