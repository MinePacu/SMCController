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

}
