//
//  SMCControllerTests.swift
//  SMCControllerTests
//
//  Created by 노현수 on 11/18/25.
//

import Testing
import Foundation
@testable import SMCController

@MainActor
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

    @Test func helperV2FanRequestUsesTypedFields() {
        let request = HelperRequest.setFan(fan: 1, rpm: 3200)

        #expect(request.fields["protocolVersion"] == .int64(2))
        #expect(request.fields["operation"] == .string("setFan"))
        #expect(request.fields["fan"] == .int64(1))
        #expect(request.fields["rpm"] == .int64(3200))
    }

    @Test func helperV2ModeRequestUsesBooleanField() {
        let request = HelperRequest.setMode(enabled: true, watchdogSeconds: 15)

        #expect(request.fields["protocolVersion"] == .int64(2))
        #expect(request.fields["operation"] == .string("setMode"))
        #expect(request.fields["enabled"] == .bool(true))
        #expect(request.fields["watchdogSeconds"] == .int64(15))
    }

    @Test func helperAvailabilityDistinguishesReadyState() {
        #expect(HelperAvailability.ready.isReady)
        #expect(!HelperAvailability.notInstalled.isReady)
        #expect(!HelperAvailability.updateRequired.isReady)
        #expect(!HelperAvailability.failed("unreachable").isReady)
    }

    @Test func controlTimingClampsIntervalAndWatchdogLease() {
        #expect(FanControlTiming.normalizedInterval(1) == 5)
        #expect(FanControlTiming.normalizedInterval(100) == 20)
        #expect(FanControlTiming.watchdogSeconds(for: 5) == 15)
        #expect(FanControlTiming.watchdogSeconds(for: 20) == 60)

        let settings = UserFanSettings(
            targetC: 70,
            minC: 30,
            maxC: 100,
            minRPM: 1200,
            maxRPM: 4000,
            interval: 100
        )
        #expect(settings.interval == 20)
    }

    @Test func manualModeFailureDoesNotStartFanWrites() async {
        let backend = FakeFanControllerBackend()
        backend.failManualEnable = true
        let controller = makeController(backend: backend)

        await #expect(throws: TestFanControllerError.manualMode) {
            try await controller.start()
        }

        #expect(backend.rpmWrites.isEmpty)
        #expect(manualModeWrites(backend.manualModeWrites, equal: [(true, 15)]))
    }

    @Test func sensorFailureStopsWritesAndRestoresAutomaticModeOnce() async throws {
        let backend = FakeFanControllerBackend()
        backend.failSensorRead = true
        var failures: [FanControlFailure] = []
        let controller = makeController(backend: backend) { failure in
            failures.append(failure)
        }

        try await controller.start()
        #expect(await waitForCondition { !failures.isEmpty })

        #expect(backend.rpmWrites.isEmpty)
        #expect(manualModeWrites(backend.manualModeWrites, equal: [(true, 15), (false, nil)]))
        #expect(failures.first?.kind == .sensorRead)
        #expect(failures.first?.restoration == .restored)
    }

    @Test func writeFailureStopsFurtherWritesAndReportsWatchdogRecovery() async throws {
        let backend = FakeFanControllerBackend()
        backend.failRPMWrite = true
        backend.failManualDisable = true
        var failures: [FanControlFailure] = []
        let controller = makeController(backend: backend) { failure in
            failures.append(failure)
        }

        try await controller.start()
        #expect(await waitForCondition { !failures.isEmpty })

        #expect(backend.rpmWrites.count == 1)
        #expect(manualModeWrites(backend.manualModeWrites, equal: [(true, 15), (false, nil)]))
        #expect(failures.first?.kind == .rpmWrite)
        #expect(failures.first?.restoration == .watchdogPending)
    }

    @Test func cancellationIsNotReportedAsControlFailure() async throws {
        let backend = FakeFanControllerBackend()
        let controller = makeController(backend: backend)

        try await controller.start()
        await controller.stop()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(manualModeWrites(backend.manualModeWrites, equal: [(true, 15), (false, nil)]))
        #expect(backend.rpmWrites.count <= 1)
    }

    @Test func intervalUpdateRearmsLeaseBeforeAcceptingLongerCadence() async throws {
        let backend = FakeFanControllerBackend()
        let controller = makeController(backend: backend)

        try await controller.start()
        let accepted = await controller.updateConfig(
            FanControllerConfig(sensorKey: "TC0P", fanIndex: 0, interval: 20)
        )
        await controller.stop()

        #expect(accepted)
        #expect(manualModeWrites(backend.manualModeWrites, equal: [(true, 15), (true, 60), (false, nil)]))
    }

    private func makeController(
        backend: FakeFanControllerBackend,
        onFailure: (@MainActor (FanControlFailure) -> Void)? = nil
    ) -> FanController {
        let io = FanControllerIO(
            readTemperature: { _ in try backend.readTemperature() },
            readMinRPM: { _ in backend.minimumRPM },
            readMaxRPM: { _ in backend.maximumRPM },
            readCurrentRPM: { _ in backend.currentRPM },
            setTargetRPM: { fan, rpm in
                try await MainActor.run { try backend.setTargetRPM(fan: fan, rpm: rpm) }
            },
            setManualMode: { enabled, watchdogSeconds in
                try await MainActor.run {
                    try backend.setManualMode(enabled: enabled, watchdogSeconds: watchdogSeconds)
                }
            }
        )
        let policy = FanPolicy(
            config: FanPolicyConfig(
                minC: 30,
                maxC: 100,
                minRPM: 1200,
                maxRPM: 4000,
                targetC: 70
            ),
            usePID: false
        )
        return FanController(
            io: io,
            policy: policy,
            config: FanControllerConfig(sensorKey: "TC0P", fanIndex: 0, interval: 5),
            onFailure: onFailure
        )
    }

    private func waitForCondition(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func manualModeWrites(
        _ actual: [(Bool, Int?)],
        equal expected: [(Bool, Int?)]
    ) -> Bool {
        actual.count == expected.count && zip(actual, expected).allSatisfy { actualEntry, expectedEntry in
            actualEntry.0 == expectedEntry.0 && actualEntry.1 == expectedEntry.1
        }
    }

}

private enum TestFanControllerError: LocalizedError {
    case manualMode
    case sensor
    case rpmWrite
    case restore

    var errorDescription: String? {
        switch self {
        case .manualMode: return "manual mode failed"
        case .sensor: return "sensor read failed"
        case .rpmWrite: return "RPM write failed"
        case .restore: return "automatic mode restore failed"
        }
    }
}

@MainActor
private final class FakeFanControllerBackend {
    var minimumRPM = 1200
    var maximumRPM = 4000
    var currentRPM = 1800
    var failManualEnable = false
    var failManualDisable = false
    var failSensorRead = false
    var failRPMWrite = false
    var rpmWrites: [(Int, Int)] = []
    var manualModeWrites: [(Bool, Int?)] = []

    func readTemperature() throws -> Double {
        if failSensorRead { throw TestFanControllerError.sensor }
        return 70
    }

    func setTargetRPM(fan: Int, rpm: Int) throws {
        rpmWrites.append((fan, rpm))
        if failRPMWrite { throw TestFanControllerError.rpmWrite }
    }

    func setManualMode(enabled: Bool, watchdogSeconds: Int?) throws {
        manualModeWrites.append((enabled, watchdogSeconds))
        if enabled && failManualEnable { throw TestFanControllerError.manualMode }
        if !enabled && failManualDisable { throw TestFanControllerError.restore }
    }
}
