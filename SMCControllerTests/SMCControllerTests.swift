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

    @Test func overheatStopsWritesAndRestoresAutomaticMode() async throws {
        let backend = FakeFanControllerBackend()
        backend.temperature = 101
        var failures: [FanControlFailure] = []
        let controller = makeController(backend: backend, criticalTempC: 100) { failure in
            failures.append(failure)
        }

        try await controller.start()
        #expect(await waitForCondition { !failures.isEmpty })

        #expect(backend.rpmWrites.isEmpty)
        #expect(manualModeWrites(backend.manualModeWrites, equal: [(true, 15), (false, nil)]))
        #expect(failures.first?.kind == .overheat)
        #expect(failures.first?.restoration == .restored)
    }

    @Test func implausibleTemperatureIsTreatedAsSensorFailure() async throws {
        let backend = FakeFanControllerBackend()
        backend.temperature = 0
        var failures: [FanControlFailure] = []
        let controller = makeController(backend: backend) { failure in
            failures.append(failure)
        }

        try await controller.start()
        #expect(await waitForCondition { !failures.isEmpty })

        #expect(backend.rpmWrites.isEmpty)
        #expect(failures.first?.kind == .sensorRead)
    }

    @Test func criticalTemperatureIsClampedToAllowedRange() {
        #expect(FanSafetyLimits.normalizedCriticalTemp(10) == 70)
        #expect(FanSafetyLimits.normalizedCriticalTemp(500) == 110)
        #expect(FanSafetyLimits.normalizedCriticalTemp(.nan) == FanSafetyLimits.defaultCriticalTempC)
        #expect(FanControllerConfig(criticalTempC: 200).criticalTempC == 110)
    }

    @Test func settingsWithoutCriticalTemperatureDecodeWithDefault() throws {
        let json = #"{"targetC":70,"minC":30,"maxC":100,"minRPM":1200,"maxRPM":4000}"#
        let decoded = try JSONDecoder().decode(UserFanSettings.self, from: Data(json.utf8))

        #expect(decoded.criticalTempC == FanSafetyLimits.defaultCriticalTempC)
    }

    @Test func smootherAppliesIncreasesImmediately() {
        var smoother = FanOutputSmoother(hysteresisC: 2, rampDownRPMPerSecond: 100)

        #expect(smoother.next(target: 2000, temperatureC: 60, elapsed: 5) == 2000)
        #expect(smoother.next(target: 3500, temperatureC: 75, elapsed: 5) == 3500)
    }

    @Test func smootherHoldsSpeedInsideHysteresisBand() {
        var smoother = FanOutputSmoother(hysteresisC: 2, rampDownRPMPerSecond: 100)

        _ = smoother.next(target: 3000, temperatureC: 75, elapsed: 5)
        #expect(smoother.next(target: 2900, temperatureC: 74, elapsed: 5) == 3000)
        #expect(smoother.next(target: 2850, temperatureC: 73.5, elapsed: 5) == 3000)
    }

    @Test func smootherLimitsRampDownRate() {
        var smoother = FanOutputSmoother(hysteresisC: 2, rampDownRPMPerSecond: 100)

        _ = smoother.next(target: 4000, temperatureC: 90, elapsed: 5)
        #expect(smoother.next(target: 1500, temperatureC: 50, elapsed: 5) == 3500)
        #expect(smoother.next(target: 1500, temperatureC: 50, elapsed: 5) == 3000)
        #expect(smoother.next(target: 2800, temperatureC: 50, elapsed: 5) == 2800)
        #expect(smoother.next(target: 2800, temperatureC: 50, elapsed: 5) == 2800)
    }

    @Test func smootherResetForgetsPreviousSpeed() {
        var smoother = FanOutputSmoother(hysteresisC: 2, rampDownRPMPerSecond: 100)

        _ = smoother.next(target: 4000, temperatureC: 90, elapsed: 5)
        smoother.reset()
        #expect(smoother.next(target: 1500, temperatureC: 50, elapsed: 5) == 1500)
    }

    @Test func historyDropsSamplesOutsideWindow() {
        var history = MonitoringHistory(window: 60)
        let start = Date(timeIntervalSince1970: 10_000)

        history.record(temperatureC: 50, fanRPM: 1500, at: start)
        history.record(temperatureC: 55, fanRPM: 1800, at: start.addingTimeInterval(30))
        history.record(temperatureC: 60, fanRPM: 2100, at: start.addingTimeInterval(70))

        #expect(history.samples.count == 2)
        #expect(history.samples.first?.temperatureC == 55)
    }

    @Test func historySkipsEmptyAndNonFiniteSamples() {
        var history = MonitoringHistory(window: 60)
        let now = Date(timeIntervalSince1970: 10_000)

        history.record(temperatureC: nil, fanRPM: nil, at: now)
        history.record(temperatureC: .nan, fanRPM: nil, at: now.addingTimeInterval(1))
        history.record(temperatureC: .nan, fanRPM: 1200, at: now.addingTimeInterval(2))

        #expect(history.samples.count == 1)
        #expect(history.samples.first?.temperatureC == nil)
        #expect(history.samples.first?.fanRPM == 1200)
    }

    @Test func presetFileRoundTripKeepsNamesAndSettings() throws {
        let settings = UserFanSettings(
            targetC: 65, minC: 30, maxC: 95, minRPM: 1300, maxRPM: 4200,
            curve: [FanCurvePoint(tempC: 40, rpm: 1300), FanCurvePoint(tempC: 80, rpm: 4000)],
            sensorKey: "TC0P",
            criticalTempC: 95
        )
        let presets = [FanPreset(id: UUID(), name: "Quiet", settings: settings, updatedAt: Date())]

        let decoded = try PresetFile.decode(PresetFile.encode(presets))

        #expect(decoded.count == 1)
        #expect(decoded.first?.name == "Quiet")
        #expect(decoded.first?.settings.curve.count == 2)
        #expect(decoded.first?.settings.criticalTempC == 95)
    }

    @Test func presetFileAcceptsBareArrayAndRejectsNewerVersion() throws {
        let bare = #"[{"name":"Loud","settings":{"targetC":70,"minC":30,"maxC":100,"minRPM":1200,"maxRPM":5000}}]"#
        #expect(try PresetFile.decode(Data(bare.utf8)).first?.name == "Loud")

        let newer = #"{"formatVersion":99,"presets":[]}"#
        #expect(throws: PresetFile.FileError.self) {
            try PresetFile.decode(Data(newer.utf8))
        }
    }

    @Test func allFansReceiveTargetsClampedToTheirOwnRange() async throws {
        let backend = FakeFanControllerBackend()
        backend.temperature = 99 // near the top of the 30...100 linear policy
        backend.maximumRPMs = [0: 4000, 1: 3000]
        let controller = makeController(backend: backend, criticalTempC: 110, fanIndices: [0, 1])

        try await controller.start()
        #expect(await waitForCondition { backend.rpmWrites.count >= 2 })
        await controller.stop()

        #expect(backend.fanMasks.first == 0b11)
        #expect(backend.rpmWrites[0].0 == 0)
        #expect(backend.rpmWrites[1].0 == 1)
        #expect(backend.rpmWrites[1].1 <= 3000)
        #expect(backend.rpmWrites[0].1 > backend.rpmWrites[1].1)
    }

    @Test func intervalUpdateCanChangeFanMask() async throws {
        let backend = FakeFanControllerBackend()
        let controller = makeController(backend: backend)

        try await controller.start()
        _ = await controller.updateConfig(
            FanControllerConfig(sensorKey: "TC0P", fanIndices: [0, 1], interval: 5)
        )
        await controller.stop()

        #expect(Array(backend.fanMasks.prefix(2)) == [0b01, 0b11])
    }

    @Test func hottestModeDrivesCurveFromMaximumSensor() async throws {
        let cool = FakeFanControllerBackend()
        cool.temperatures = ["TC0P": 40]
        let coolController = makeController(backend: cool)
        try await coolController.start()
        #expect(await waitForCondition { !cool.rpmWrites.isEmpty })
        await coolController.stop()

        let hot = FakeFanControllerBackend()
        hot.temperatures = ["TC0P": 40, "TG0D": 80]
        let hotController = makeController(
            backend: hot,
            additionalSensorKeys: ["TG0D"],
            aggregation: .maximum
        )
        try await hotController.start()
        #expect(await waitForCondition { !hot.rpmWrites.isEmpty })
        await hotController.stop()

        #expect(hot.rpmWrites[0].1 > cool.rpmWrites[0].1)
    }

    @Test func failingExtraSensorIsSkippedButPrimaryFailureStopsControl() async throws {
        let backend = FakeFanControllerBackend()
        backend.failingSensorKeys = ["TG0D"]
        var failures: [FanControlFailure] = []
        let controller = makeController(
            backend: backend,
            additionalSensorKeys: ["TG0D"],
            aggregation: .average
        ) { failures.append($0) }

        try await controller.start()
        #expect(await waitForCondition { !backend.rpmWrites.isEmpty })
        await controller.stop()
        #expect(failures.isEmpty)

        let broken = FakeFanControllerBackend()
        broken.failingSensorKeys = ["TC0P"]
        var brokenFailures: [FanControlFailure] = []
        let brokenController = makeController(
            backend: broken,
            additionalSensorKeys: ["TG0D"],
            aggregation: .average
        ) { brokenFailures.append($0) }

        try await brokenController.start()
        #expect(await waitForCondition { !brokenFailures.isEmpty })
        #expect(brokenFailures.first?.kind == .sensorRead)
        #expect(broken.rpmWrites.isEmpty)
    }

    @Test func averageModeStillStopsWhenAnySensorIsCritical() async throws {
        let backend = FakeFanControllerBackend()
        backend.temperatures = ["TC0P": 50, "TG0D": 104]
        var failures: [FanControlFailure] = []
        let controller = makeController(
            backend: backend,
            criticalTempC: 100,
            additionalSensorKeys: ["TG0D"],
            aggregation: .average
        ) { failures.append($0) }

        try await controller.start()
        #expect(await waitForCondition { !failures.isEmpty })

        #expect(failures.first?.kind == .overheat)
        #expect(backend.rpmWrites.isEmpty)
    }

    @Test func sensorAggregationCombinesValues() {
        #expect(SensorAggregation.primary.combine([50, 80]) == 50)
        #expect(SensorAggregation.maximum.combine([50, 80, 60]) == 80)
        #expect(SensorAggregation.average.combine([50, 70]) == 60)
        #expect(SensorAggregation.average.combine([]) == nil)
    }

    @Test func fanSelectionResolvesIndicesAndMask() {
        #expect(FanSelection.indices(controlAllFans: true, fanIndex: 0, fanCount: 2) == [0, 1])
        #expect(FanSelection.indices(controlAllFans: false, fanIndex: 5, fanCount: 2) == [1])
        #expect(FanSelection.indices(controlAllFans: true, fanIndex: 0, fanCount: nil) == [0])
        #expect(FanSelection.indices(controlAllFans: false, fanIndex: 1, fanCount: nil) == [1])
        #expect(FanSelection.mask(for: [0, 1]) == 0b11)
        #expect(FanSelection.mask(for: [2]) == 0b100)
        #expect(FanSelection.normalized([3, 3, -1, 42]) == [3])
        #expect(FanSelection.normalized([]) == [0])
    }

    @Test func fanRangeIntersectsPolicyAndHardware() {
        #expect(FanRangeResolver.range(policyMin: 1200, policyMax: 5000, hardwareMin: 1300, hardwareMax: 4000) == 1300...4000)
        #expect(FanRangeResolver.range(policyMin: 1200, policyMax: 5000, hardwareMin: nil, hardwareMax: nil) == 1200...5000)
        // No overlap: the hardware range wins.
        #expect(FanRangeResolver.range(policyMin: 5000, policyMax: 6000, hardwareMin: 1200, hardwareMax: 4000) == 1200...4000)
    }

    @Test func settingsWithoutMultiFanFieldsDecodeWithDefaults() throws {
        let json = #"{"targetC":70,"minC":30,"maxC":100,"minRPM":1200,"maxRPM":4000,"sensorAggregation":"futureMode"}"#
        let decoded = try JSONDecoder().decode(UserFanSettings.self, from: Data(json.utf8))

        #expect(!decoded.controlAllFans)
        #expect(decoded.controlSensorKeys.isEmpty)
        #expect(decoded.sensorAggregation == .primary)
    }

    @Test func helperVersionRequiresAllFanSupport() {
        #expect(HelperVersion.isSupported("2.1"))
        #expect(HelperVersion.isSupported("2.3.4"))
        #expect(!HelperVersion.isSupported("2.0"))
        #expect(!HelperVersion.isSupported("2"))
        #expect(!HelperVersion.isSupported("3.0"))
        #expect(!HelperVersion.isSupported("garbage"))
    }

    @Test func helperModeRequestCarriesFanMaskOnlyWhenEnabling() {
        #expect(HelperRequest.setMode(enabled: true, watchdogSeconds: 15, fanMask: 3).fields["fanMask"] == .int64(3))
        #expect(HelperRequest.setMode(enabled: false, fanMask: 3).fields["fanMask"] == nil)
    }

    @Test func transientSensorFailureIsRetriedWithinTheCycle() async throws {
        let backend = FakeFanControllerBackend()
        backend.transientFailures = ["TC0P": 2]
        var failures: [FanControlFailure] = []
        let controller = makeController(backend: backend) { failures.append($0) }

        try await controller.start()
        #expect(await waitForCondition { !backend.rpmWrites.isEmpty })
        await controller.stop()

        #expect(failures.isEmpty)
        #expect(backend.sensorReads["TC0P"] == 3)
    }

    @Test func sensorFailureBeforeAnyGoodReadingStopsAfterRetries() async throws {
        let backend = FakeFanControllerBackend()
        backend.transientFailures = ["TC0P": 3]
        var failures: [FanControlFailure] = []
        let controller = makeController(backend: backend) { failures.append($0) }

        try await controller.start()
        #expect(await waitForCondition { !failures.isEmpty })

        #expect(failures.first?.kind == .sensorRead)
        #expect(backend.sensorReads["TC0P"] == 3)
        #expect(backend.rpmWrites.isEmpty)
    }

    @Test func sensorOutageHoldsLastSpeedThenRecovers() async throws {
        let backend = FakeFanControllerBackend()
        var failures: [FanControlFailure] = []
        var statuses: [SensorReadStatus] = []
        let controller = makeController(
            backend: backend,
            onFailure: { failures.append($0) },
            onSensorStatus: { statuses.append($0) }
        )

        try await controller.start()
        #expect(await waitForCondition { backend.rpmWrites.count == 1 })
        let firstRPM = backend.rpmWrites[0].1

        // Every attempt of the next cycle fails, then the sensor comes back.
        backend.transientFailures = ["TC0P": 3]
        backend.temperature = 90
        #expect(await waitForCondition(timeout: 7) { backend.rpmWrites.count == 2 })

        #expect(failures.isEmpty)
        #expect(backend.rpmWrites[1].1 == firstRPM)
        #expect(statuses.first == .degraded(key: "TC0P", message: "sensor read failed"))
        await controller.stop()
    }

    @Test func retryPolicyHoldsOnlyForShortOutagesAfterAGoodReading() {
        let policy = SensorRetryPolicy(maxConsecutiveFailedCycles: 2, maxOutage: 30)
        let good = Date(timeIntervalSince1970: 1_000)

        #expect(!policy.allowsHolding(consecutiveFailedCycles: 1, lastGoodReading: nil, now: good))
        #expect(policy.allowsHolding(consecutiveFailedCycles: 1, lastGoodReading: good, now: good.addingTimeInterval(5)))
        #expect(policy.allowsHolding(consecutiveFailedCycles: 2, lastGoodReading: good, now: good.addingTimeInterval(20)))
        #expect(!policy.allowsHolding(consecutiveFailedCycles: 3, lastGoodReading: good, now: good.addingTimeInterval(15)))
        #expect(!policy.allowsHolding(consecutiveFailedCycles: 1, lastGoodReading: good, now: good.addingTimeInterval(31)))
        #expect(SensorRetryPolicy(attemptsPerCycle: 0).attemptsPerCycle == 1)
    }

    private func makeController(
        backend: FakeFanControllerBackend,
        criticalTempC: Double = FanSafetyLimits.defaultCriticalTempC,
        fanIndices: [Int] = [0],
        additionalSensorKeys: [String] = [],
        aggregation: SensorAggregation = .primary,
        retryPolicy: SensorRetryPolicy = SensorRetryPolicy(retryDelay: 0),
        onFailure: (@MainActor (FanControlFailure) -> Void)? = nil,
        onSensorStatus: (@MainActor (SensorReadStatus) -> Void)? = nil
    ) -> FanController {
        let io = FanControllerIO(
            readTemperature: { key in try backend.readTemperature(key: key) },
            readMinRPM: { fan in backend.minimumRPMs[fan] ?? backend.minimumRPM },
            readMaxRPM: { fan in backend.maximumRPMs[fan] ?? backend.maximumRPM },
            readCurrentRPM: { _ in backend.currentRPM },
            setTargetRPM: { fan, rpm in
                try await MainActor.run { try backend.setTargetRPM(fan: fan, rpm: rpm) }
            },
            setManualMode: { enabled, watchdogSeconds, fanMask in
                try await MainActor.run {
                    try backend.setManualMode(
                        enabled: enabled,
                        watchdogSeconds: watchdogSeconds,
                        fanMask: fanMask
                    )
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
            config: FanControllerConfig(
                sensorKey: "TC0P",
                fanIndices: fanIndices,
                interval: 5,
                criticalTempC: criticalTempC,
                additionalSensorKeys: additionalSensorKeys,
                aggregation: aggregation
            ),
            retryPolicy: retryPolicy,
            onFailure: onFailure,
            onSensorStatus: onSensorStatus
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
    var temperature = 70.0
    var temperatures: [String: Double] = [:]
    var failingSensorKeys: Set<String> = []
    /// Fails this many upcoming reads per key, then succeeds.
    var transientFailures: [String: Int] = [:]
    var sensorReads: [String: Int] = [:]
    var minimumRPMs: [Int: Int] = [:]
    var maximumRPMs: [Int: Int] = [:]
    var rpmWrites: [(Int, Int)] = []
    var manualModeWrites: [(Bool, Int?)] = []
    var fanMasks: [Int] = []

    func readTemperature(key: String) throws -> Double {
        sensorReads[key, default: 0] += 1
        if let remaining = transientFailures[key], remaining > 0 {
            transientFailures[key] = remaining - 1
            throw TestFanControllerError.sensor
        }
        if failSensorRead || failingSensorKeys.contains(key) { throw TestFanControllerError.sensor }
        return temperatures[key] ?? temperature
    }

    func setTargetRPM(fan: Int, rpm: Int) throws {
        rpmWrites.append((fan, rpm))
        if failRPMWrite { throw TestFanControllerError.rpmWrite }
    }

    func setManualMode(enabled: Bool, watchdogSeconds: Int?, fanMask: Int) throws {
        manualModeWrites.append((enabled, watchdogSeconds))
        fanMasks.append(fanMask)
        if enabled && failManualEnable { throw TestFanControllerError.manualMode }
        if !enabled && failManualDisable { throw TestFanControllerError.restore }
    }
}
