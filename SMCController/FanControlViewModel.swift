//
//  FanControlViewModel.swift
//  SMCController
//

import Foundation
import Observation

struct HIDSensorDetail: Identifiable {
    let id = UUID()
    let name: String
    let location: String
    let usagePage: Int
    let usage: Int
    let value: Double
}

@Observable
final class FanControlViewModel {
    // MARK: - Constants
    private let absoluteMaxC: Double = 120
    private let minPollInterval: Double = 0.5 // UI 폴링 최소 주기(초)
    private let minPoints = 2
    private let maxPoints = 12

    // MARK: - Curve
    var curve: [FanCurvePoint] = [
        FanCurvePoint(tempC: 40, rpm: 1200),
        FanCurvePoint(tempC: 60, rpm: 2000),
        FanCurvePoint(tempC: 75, rpm: 3000),
        FanCurvePoint(tempC: 90, rpm: 4000),
        FanCurvePoint(tempC: 105, rpm: 5000)
    ] {
        didSet { clampCurvePointsIfNeeded() }
    }

    // MARK: - UI state
    var isRunning: Bool = false
    var monitoringError: String?
    var isMonitoring: Bool = false

    // MARK: - User settings
    var targetC: Double = 70 {
        didSet { targetC = min(max(targetC, minC), maxC) }
    }

    var minC: Double = 25 {
        didSet {
            if minC > maxC { minC = maxC }
            clampCurvePointsIfNeeded()
        }
    }

    var maxC: Double = 120 {
        didSet {
            if maxC > absoluteMaxC { maxC = absoluteMaxC }
            if maxC < minC { maxC = minC }
            clampCurvePointsIfNeeded()
        }
    }

    var minRPM: Double = 1200 {
        didSet {
            if minRPM > maxRPM { minRPM = maxRPM }
            clampCurvePointsIfNeeded()
        }
    }

    var maxRPM: Double = 5500 {
        didSet {
            if maxRPM < minRPM { maxRPM = minRPM }
            clampCurvePointsIfNeeded()
        }
    }

    var usePID: Bool = false
    var kp: Double = 50
    var ki: Double = 0
    var kd: Double = 0

    var sensorKey: String = "Tc0P"
    // Comma-separated extra sensor keys to read-only monitor (for new SoCs/custom sensors)
    var extraSensorKeysText: String = "" {
        didSet {
            extraSensorKeys = extraSensorKeysText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
    var extraSensorKeys: [String] = []

    var fanIndex: Int = 0 {
        didSet { loadHardwareMaxRPM() }
    }

    // 제어 루프 주기(초). 너무 작지 않게 사용 권장
    var interval: Double = 1.0 {
        didSet {
            // 폴링 하한을 지나치게 낮추지 않도록 안내
            if interval < 0.2 { interval = 0.2 }
        }
    }

    // UI 표시용 (기존)
    var lastTempC: Double?
    var lastAppliedRPM: Int?

    // UI 표시용 (추가 모니터링)
    var cpuAvgC: Double?
    var cpuHotC: Double?
    var gpuC: Double?
    var fanRPM: Int?
    
    // HID sensors for debug UI (Apple Silicon only)
    var hidSensors: [String: Double] = [:]
    var hidSensorDetails: [HIDSensorDetail] = []

    // MARK: - Services
    private let api = SMCControllerAPI()

    // ViewModel 수명 동안 유지(메인 액터에서만 접근)
    @MainActor
    var smc: SMCService?

    // Sensor polling layer
    private var sensorPoller: SensorPoller?
    
    // Direct SMC polling timer (for Apple Silicon temperature monitoring)
    private var smcPollingTimer: Timer?
    
    // HID sensor poller for Apple Silicon
    private var hidSensorPoller: HIDSensorPoller?
    
    // Track first HID sensor update for debug logging
    private var hidFirstRun = true

    private var isClamping = false

    // Sensor key cache after probing
    private var probedCPUHotKey: String?
    private var probedGPUKey: String?
    
    // Fan RPM limits cache (key: "fanRPMLimits_\(fanIndex)")
    private struct FanRPMLimits: Codable {
        let minRPM: Int
        let maxRPM: Int
        let timestamp: Date
    }

    // MARK: - Init
    init() {
        if maxC > absoluteMaxC { maxC = absoluteMaxC }
        clampCurvePointsIfNeeded()
        Task { @MainActor in
            do {
                print("[ViewModel] Initializing...")
                // Try SMC first (works on both Intel and Apple Silicon with correct structures)
                self.smc = try SMCService()
                print("[ViewModel] SMC initialized successfully")
                
                #if arch(arm64)
                // Apple Silicon: Auto-detect temperature sensor key
                print("[ViewModel] Apple Silicon detected - detecting temperature sensor")
                self.sensorKey = detectAppleSiliconTempSensor() ?? "Tp09"
                print("[ViewModel] Using temperature sensor: \(self.sensorKey)")
                #endif
                
                await loadHardwareMaxRPM()
                
                #if !arch(arm64)
                // Intel: Probe optional sensors
                await probeOptionalSensorsIfNeeded()
                #endif
            } catch {
                print("[ViewModel] SMC initialization: \(error)")
            }
        }
    }

    // MARK: - Curve editing helpers used by FanControlView
    func canAddPoint() -> Bool {
        curve.count < maxPoints
    }

    func canRemovePoint() -> Bool {
        curve.count > minPoints
    }

    func addPoint() {
        guard canAddPoint() else { return }
        var newPoint: FanCurvePoint

        let sorted = curve.sorted()
        if sorted.count >= 2 {
            let a = sorted[sorted.count - 2]
            let b = sorted[sorted.count - 1]
            let midT = min(max((a.tempC + b.tempC) / 2.0, minC), maxC)
            let midR = min(max(Double(a.rpm + b.rpm) / 2.0, minRPM), maxRPM)
            newPoint = FanCurvePoint(tempC: round(midT), rpm: Int(round(midR)))
        } else if let only = sorted.first {
            let t = min(max(only.tempC + 5.0, minC), maxC)
            let r = min(max(Double(only.rpm) + 200.0, minRPM), maxRPM)
            newPoint = FanCurvePoint(tempC: round(t), rpm: Int(round(r)))
        } else {
            let t = min(max((minC + maxC) / 2.0, minC), maxC)
            let r = min(max((minRPM + maxRPM) / 2.0, minRPM), maxRPM)
            newPoint = FanCurvePoint(tempC: round(t), rpm: Int(round(r)))
        }

        curve.append(newPoint)
        curve.sort()
        clampCurvePointsIfNeeded()
    }

    func removePoint() {
        guard canRemovePoint() else { return }
        curve.removeLast()
        clampCurvePointsIfNeeded()
    }
    
    // Refresh fan limits from SMC (bypassing cache)
    func refreshFanLimits() {
        let cacheKey = "fanRPMLimits_\(fanIndex)"
        UserDefaults.standard.removeObject(forKey: cacheKey)
        print("[ViewModel] Cleared cache for fan \(fanIndex), reloading from SMC...")
        loadHardwareMaxRPM()
    }

    // MARK: - Actions
    func start() {
        Task { @MainActor in
            do {
                let settings = UserFanSettings(
                    targetC: targetC,
                    minC: minC,
                    maxC: maxC,
                    minRPM: Int(minRPM),
                    maxRPM: Int(maxRPM),
                    curve: curve,
                    usePID: usePID,
                    kp: kp, ki: ki, kd: kd,
                    sensorKey: sensorKey,
                    fanIndex: fanIndex,
                    interval: interval
                )
                // Pass shared SMC instance to avoid creating/closing connections
                try await api.startInternal(settings: settings, sharedSMC: smc)
                isRunning = true
                startMonitoring()
            } catch {
                isRunning = false
                print("Start failed: \(error)")
            }
        }
    }

    func stop() {
        Task { @MainActor in
            await api.stop()
            isRunning = false
            stopMonitoring()
        }
    }

    func applyChanges() {
        Task {
            let settings = UserFanSettings(
                targetC: targetC,
                minC: minC,
                maxC: maxC,
                minRPM: Int(minRPM),
                maxRPM: Int(maxRPM),
                curve: curve,
                usePID: usePID,
                kp: kp, ki: ki, kd: kd,
                sensorKey: sensorKey,
                fanIndex: fanIndex,
                interval: interval
            )
            await api.update(settings: settings)
        }
    }

    // Debug: start only the sensor polling without issuing any fan writes.
    func startMonitoringOnly() {
        isRunning = false
        startMonitoring()
    }

    // MARK: - Hardware sync
    private func loadHardwareMaxRPM() {
        Task { @MainActor in
            guard let smc else {
                monitoringError = "⚠️ SMC not available"
                return
            }
            
            var index = fanIndex
            
            // Try to read fan count
            do {
                let count = try smc.fanCount()
                if count == 0 {
                    monitoringError = "⚠️ No fans detected"
                    return
                }
                let clamped = min(max(0, index), count - 1)
                if clamped != index {
                    index = clamped
                    fanIndex = clamped
                }
            } catch {
                // Can't read fan count, continue anyway
                print("[ViewModel] ⚠️ Cannot read fan count: \(error)")
            }
            
            // Load fan limits from SMC
            let success = loadFanLimitsFromSMC(fanIndex: index)
            
            #if arch(arm64)
            if success {
                // Apple Silicon: Fan control is experimental
                monitoringError = "⚠️ Apple Silicon: Fan control is experimental. Use with caution."
            }
            #else
            // Intel: Clear error if successful
            if success {
                monitoringError = nil
            }
            #endif
        }
    }
    
    @discardableResult
    private func loadFanLimitsFromSMC(fanIndex: Int) -> Bool {
        print("[ViewModel] loadFanLimitsFromSMC called for fan \(fanIndex)")
        
        // Check cache first
        let cacheKey = "fanRPMLimits_\(fanIndex)"
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(FanRPMLimits.self, from: cachedData) {
            // Use cache if it's less than 30 days old
            let cacheAge = Date().timeIntervalSince(cached.timestamp)
            if cacheAge < 30 * 24 * 3600 {
                print("[ViewModel] ✅ Using cached fan limits for fan \(fanIndex): min=\(cached.minRPM), max=\(cached.maxRPM)")
                self.minRPM = Double(cached.minRPM)
                self.maxRPM = Double(cached.maxRPM)
                self.clampCurvePointsIfNeeded()
                return true
            } else {
                print("[ViewModel] ⚠️ Cache expired for fan \(fanIndex), refreshing from SMC")
            }
        } else {
            print("[ViewModel] 📭 No cache found for fan \(fanIndex)")
        }
        
        // Read from SMC
        guard let smc else {
            print("[ViewModel] ❌ SMC service not available")
            return false
        }
        
        var didReadMin = false
        var didReadMax = false
        var hwMin: Int = 0
        var hwMax: Int = 0
        
        // Read min RPM
        print("[ViewModel] 🔍 Attempting to read min RPM for fan \(fanIndex)...")
        do {
            let min = try smc.minRPM(fan: fanIndex)
            hwMin = min
            didReadMin = true
            print("[ViewModel] ✅ Read fan \(fanIndex) min RPM from SMC: \(min)")
        } catch {
            print("[ViewModel] ❌ Failed to read min RPM: \(error)")
        }
        
        // Read max RPM
        print("[ViewModel] 🔍 Attempting to read max RPM for fan \(fanIndex)...")
        do {
            let max = try smc.maxRPM(fan: fanIndex)
            hwMax = max
            didReadMax = true
            print("[ViewModel] ✅ Read fan \(fanIndex) max RPM from SMC: \(max)")
        } catch {
            print("[ViewModel] ❌ Failed to read max RPM: \(error)")
        }
        
        // Update UI and cache if we got valid values
        if didReadMin && didReadMax && hwMin > 0 && hwMax > hwMin {
            print("[ViewModel] ✅ Valid fan limits: min=\(hwMin), max=\(hwMax)")
            self.minRPM = Double(hwMin)
            self.maxRPM = Double(hwMax)
            self.clampCurvePointsIfNeeded()
            
            // Cache the values
            let limits = FanRPMLimits(minRPM: hwMin, maxRPM: hwMax, timestamp: Date())
            if let encoded = try? JSONEncoder().encode(limits) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
                print("[ViewModel] 💾 Cached fan \(fanIndex) limits: min=\(hwMin), max=\(hwMax)")
            }
            
            monitoringError = nil
            return true
        } else {
            // Could not read fan limits - fan may not exist at this index
            print("[ViewModel] ❌ Invalid fan limits or read failed: didReadMin=\(didReadMin), didReadMax=\(didReadMax), min=\(hwMin), max=\(hwMax)")
            monitoringError = "Fan \(fanIndex) not accessible (try different fan index or check hardware)"
            return false
        }
    }

    // MARK: - Monitoring (read-only UI polling)
    private func startMonitoring() {
        stopMonitoring()

        Task { @MainActor in
            isMonitoring = true
            monitoringError = "Starting monitoring..."

            #if arch(arm64)
            // Apple Silicon: Use HID for temperatures, SMC for fan RPM
            print("[ViewModel] Apple Silicon - using HID for temps, SMC for fans")
            startHIDMonitoring()
            
            #else
            // Intel: Use SMC for everything
            // Ensure SMC is initialized
            if smc == nil {
                do {
                    smc = try SMCService()
                } catch {
                    monitoringError = "SMC open failed (monitoring unavailable)"
                    isMonitoring = false
                    return
                }
            }
            
            guard let reader = smc else {
                monitoringError = "SMC not available"
                isMonitoring = false
                return
            }

            startSMCMonitoring(reader: reader)
            #endif
        }
    }
    
    private func startSMCMonitoring(reader: SMCService) {
        Task { @MainActor in
            // Validate fan accessibility before starting poller
            do {
                let count = try reader.fanCount()
                if count == 0 {
                    monitoringError = "No fans detected - monitoring CPU/GPU only"
                } else if fanIndex >= count {
                    monitoringError = "Fan index \(fanIndex) out of range (0-\(count-1)) - using fan 0"
                    fanIndex = 0
                }
            } catch {
                if (try? reader.currentRPM(fan: fanIndex)) == nil {
                    monitoringError = "Fan \(fanIndex) not accessible - monitoring CPU/GPU only"
                }
            }

            await probeOptionalSensorsIfNeeded(using: reader)

            let poller = SensorPoller(
                smc: reader,
                interval: max(minPollInterval, interval),
                definitions: sensorDefinitions(),
                extraKeys: extraSensorKeys
            )
            sensorPoller = poller

            monitoringError = nil

            poller.start { [weak self] readings in
                guard let self else { return }

                let cpuAvg = readings.first(where: { $0.name == "CPU Avg" })?.value
                let cpuHot = readings.first(where: { $0.name == "CPU Hot" })?.value
                let gpu = readings.first(where: { $0.name == "GPU" })?.value
                let rpm = readings.first(where: { $0.name == "Fan RPM" })?.value

                self.cpuAvgC = cpuAvg
                self.cpuHotC = cpuHot
                self.gpuC = gpu
                if let rpm {
                    let intRPM = Int(round(rpm))
                    self.fanRPM = intRPM
                    self.lastAppliedRPM = intRPM
                }
                if let cpuAvg {
                    self.lastTempC = cpuAvg
                }
            } onError: { [weak self] err in
                self?.monitoringError = err
            }
        }
    }
    
    private func startHIDMonitoring() {
        Task { @MainActor in
            // Try SMC first for temperatures on Apple Silicon
            if let smc = self.smc {
                print("[ViewModel] Apple Silicon: Trying SMC for temperatures")
                if tryReadSMCTemperatures() {
                    print("[ViewModel] ✅ Using SMC for temperatures on Apple Silicon")
                    // Start SMC polling for temps + fan
                    startSMCTemperaturePolling()
                    return
                }
                print("[ViewModel] ⚠️ SMC temps not available, falling back to HID")
            }
            
            // Fallback to HID if SMC doesn't have temperature sensors
            let poller = HIDSensorPoller(interval: max(minPollInterval, interval))
            hidSensorPoller = poller
            
            poller.start { [weak self] sensors in
                guard let self else { return }
                
                // Update hidSensors for debug UI
                self.hidSensors = sensors
                
                // Collect detailed sensor info
                self.updateHIDSensorDetails()
                
                print("[ViewModel] HID update: \(sensors.count) sensors")
                
                if self.hidFirstRun {
                    for (name, value) in sensors.sorted(by: { $0.key < $1.key }) {
                    }
                    self.hidFirstRun = false
                }
                
                var cpuTemp: Double?
                var gpuTemp: Double?
                var maxDieTemp: Double?
                
                for (name, value) in sensors {
                    let nameLower = name.lowercased()
                    
                    // Match CPU sensors based on Stats patterns
                    if name.hasPrefix("pACC MTR Temp") || name.hasPrefix("eACC MTR Temp") {
                        if cpuTemp == nil || value > cpuTemp! {
                            cpuTemp = value
                        }
                    }
                    
                    // Match GPU sensors
                    if name.hasPrefix("GPU MTR Temp") {
                        if gpuTemp == nil || value > gpuTemp! {
                            gpuTemp = value
                        }
                    }
                    
                    // Track max die temp for fallback
                    if name.contains("tdie") {
                        if maxDieTemp == nil || value > maxDieTemp! {
                            maxDieTemp = value
                        }
                    }
                }
                
                // Fallback: if no explicit GPU sensor, use max die temp
                if gpuTemp == nil && maxDieTemp != nil {
                    gpuTemp = maxDieTemp
                }
                
                self.cpuAvgC = cpuTemp
                self.cpuHotC = cpuTemp
                self.gpuC = gpuTemp
                self.lastTempC = cpuTemp
                
                // Try to read fan RPM from SMC on Apple Silicon
                if let smc = self.smc {
                    do {
                        let rpm = try smc.currentRPM(fan: self.fanIndex)
                        self.fanRPM = rpm
                        print("[ViewModel] Fan RPM from SMC: \(rpm)")
                    } catch {
                        // Fan read failed - not critical
                        self.fanRPM = nil
                    }
                } else {
                    self.fanRPM = nil
                }
                
                if cpuTemp != nil {
                    let fanInfo = self.fanRPM != nil ? ", Fan: \(self.fanRPM!) RPM" : ""
                    self.monitoringError = "Apple Silicon: \(sensors.count) HID sensors\(fanInfo)"
                } else {
                    self.monitoringError = "No temperature sensors found"
                }
            } onError: { [weak self] err in
                self?.monitoringError = err
            }
        }
    }

    private func stopMonitoring() {
        sensorPoller?.stop()
        sensorPoller = nil
        smcPollingTimer?.invalidate()
        smcPollingTimer = nil
        hidSensorPoller?.stop()
        hidSensorPoller = nil
        hidFirstRun = true  // Reset debug flag for next monitoring session
        isMonitoring = false
    }

    private func sensorDefinitions() -> [SensorDefinition] {
        var defs: [SensorDefinition] = []

        // CPU Avg: user key + common fallbacks
        var cpuKeys: [String] = []
        cpuKeys.append(sensorKey)
        cpuKeys.append(contentsOf: ["TC0P", "Tc0P", "TC0E", "TC0D", "TC0H"])
        let uniqCPU = Array(NSOrderedSet(array: cpuKeys)) as! [String]
        defs.append(
            SensorDefinition(name: "CPU Avg",
                             keys: uniqCPU,
                             unit: .celsius,
                             kind: .temperature,
                             transform: { $0 })
        )

        let hotKeys = probedCPUHotKey.map { [$0] } ?? ["TC0H", "TC0D", "TC0E", "TC0F", "Tc0E", "Tc0F"]
        defs.append(
            SensorDefinition(name: "CPU Hot",
                             keys: hotKeys,
                             unit: .celsius,
                             kind: .temperature,
                             transform: { $0 })
        )

        let gpuKeys = probedGPUKey.map { [$0] } ?? ["TG0D", "TG0P", "TG1D", "TG1P", "TGDD", "TG0H"]
        defs.append(
            SensorDefinition(name: "GPU",
                             keys: gpuKeys,
                             unit: .celsius,
                             kind: .temperature,
                             transform: { $0 })
        )

        defs.append(
            SensorDefinition(name: "Fan RPM",
                             keys: [],
                             unit: .rpm,
                             kind: .rpm(fanIndex: fanIndex),
                             transform: { $0 })
        )

        return defs
    }

    // MARK: - Optional sensor probing
    @MainActor
    private func probeOptionalSensorsIfNeeded(using smc: SMCService? = nil) {
        // If provided a reader, use it; else try the main smc if available.
        let reader = smc ?? self.smc

        guard let reader else { return }

        // Common CPU hottest keys to try (device dependent)
        if probedCPUHotKey == nil {
            let cpuHotCandidates = ["TC0H", "TC0D", "TC0E", "TC0F", "Tc0E", "Tc0F"]
            for key in cpuHotCandidates {
                if let val = try? reader.readTemperatureC(key: key), !val.isNaN {
                    probedCPUHotKey = key
                    break
                }
            }
        }

        // Common GPU temp keys to try
        if probedGPUKey == nil {
            // M4 GPU keys: Tg0G, Tg0H, Tg0K, Tg0L, Tg0d, Tg0e, Tg0j, Tg0k
            // M1/M2/M3 GPU keys: Tg05, Tg0D, Tg0L, Tg0T, Tg0f, Tg0j
            // Intel GPU keys: TG0D, TG0P, TG1D, TG1P, TGDD, TG0H
            let gpuCandidates = [
                "Tg0G", "Tg0H", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k",  // M4
                "Tg05", "Tg0D", "Tg0f",  // M1/M2/M3
                "TG0D", "TG0P", "TG1D", "TG1P", "TGDD", "TG0H"  // Intel
            ]
            for key in gpuCandidates {
                if let val = try? reader.readTemperatureC(key: key), !val.isNaN {
                    probedGPUKey = key
                    print("[ViewModel] Found GPU key: \(key) = \(val)°C")
                    break
                }
            }
        }
    }

    // MARK: - Helpers
    private func clampCurvePointsIfNeeded() {
        if isClamping { return }
        isClamping = true
        defer { isClamping = false }

        let cappedMaxC = min(maxC, absoluteMaxC)
        var changed = false
        for i in curve.indices {
            var p = curve[i]
            let oldP = p
            p.tempC = min(max(p.tempC, minC), cappedMaxC)
            p.rpm = Int(min(max(Double(p.rpm), minRPM), maxRPM))
            if p != oldP {
                curve[i] = p
                changed = true
            }
        }
        if changed { curve.sort() }
    }
    
    private func updateHIDSensorDetails() {
        #if arch(arm64)
        guard let conn = hid_open() else { return }
        defer { hid_close(conn) }
        
        var sensors: [HIDSensorInfo] = Array(repeating: HIDSensorInfo(name: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0), location: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0), primaryUsagePage: 0, primaryUsage: 0, value: 0), count: 64)
        
        let count = hid_enumerate_sensors(conn, HIDSensorTypeTemperature, &sensors, 64)
        
        var details: [HIDSensorDetail] = []
        for i in 0..<Int(count) {
            let namePtr = withUnsafeBytes(of: sensors[i].name) {
                $0.baseAddress!.assumingMemoryBound(to: CChar.self)
            }
            let locationPtr = withUnsafeBytes(of: sensors[i].location) {
                $0.baseAddress!.assumingMemoryBound(to: CChar.self)
            }
            
            if let name = String(cString: namePtr, encoding: .utf8),
               let location = String(cString: locationPtr, encoding: .utf8) {
                details.append(HIDSensorDetail(
                    name: name,
                    location: location,
                    usagePage: Int(sensors[i].primaryUsagePage),
                    usage: Int(sensors[i].primaryUsage),
                    value: sensors[i].value
                ))
            }
        }
        
        self.hidSensorDetails = details
        #endif
    }
    
    // MARK: - SMC Temperature Support (Apple Silicon)
    
    // MARK: - Apple Silicon Temperature Sensor Detection
    
    private func detectAppleSiliconTempSensor() -> String? {
        guard let smc = self.smc else { return nil }
        
        // Priority order: PMU sensors -> P-core sensors
        let candidateKeys = [
            "Tp09",  // PMU Die 9 (most common)
            "Tp0T",  // PMU Die T
            "Tp01",  // PMU Die 1
            "Tp0a",  // P-Core Cluster 0
            "Tp0b",  // P-Core Cluster 1
            "Tp05",  // PMU Die 5
            "Tp0D",  // PMU Die D
        ]
        
        for key in candidateKeys {
            do {
                let temp = try smc.readTemperatureC(key: key)
                if temp > 0 && temp < 150 {
                    print("[ViewModel] ✅ Detected working temp sensor: \(key) = \(temp)°C")
                    return key
                }
            } catch {
                // Try next key
            }
        }
        
        print("[ViewModel] ⚠️ No working temp sensor found, using default 'Tp09'")
        return "Tp09"
    }
    
    private func tryReadSMCTemperatures() -> Bool {
        guard let smc = self.smc else { return false }
        
        // Common M-series temperature keys
        let tempKeys = ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P"]
        
        for key in tempKeys {
            do {
                let temp = try smc.readTemperatureC(key: key)
                if temp > 0 && temp < 200 {
                    print("[ViewModel] ✅ SMC temp key '\(key)' works: \(temp)°C")
                    return true
                }
            } catch {
                // Key doesn't exist, continue
            }
        }
        
        return false
    }
    
    private func startSMCTemperaturePolling() {
        Task { @MainActor in
            guard let smc = self.smc else { return }
            
            print("[ViewModel] Starting SMC temperature polling for Apple Silicon")
            
            // Stop any existing poller
            sensorPoller?.stop()
            sensorPoller = nil
            
            // Use Timer to poll SMC directly (like SMCSensorDebugView)
            let timer = Timer.scheduledTimer(withTimeInterval: max(minPollInterval, interval), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let smc = self.smc else { return }
                    
                    // Read M-series P-core cluster temperatures (Tp0a-d for M4)
                    var pCoreTemps: [Double] = []
                    let pCoreKeys = ["Tp0a", "Tp0b", "Tp0c", "Tp0d", "Tp1a", "Tp1b", "Tp1c", "Tp1d"]
                    for key in pCoreKeys {
                        if let temp = try? smc.readTemperatureC(key: key), temp > 0 && temp < 150 {
                            pCoreTemps.append(temp)
                        }
                    }
                    
                    // Read M-series E-core cluster temperatures (Tp0e-h for M4)
                    var eCoreTemps: [Double] = []
                    let eCoreKeys = ["Tp0e", "Tp0f", "Tp0g", "Tp0h", "Tp1e", "Tp1f", "Tp1g", "Tp1h", "Tp2e", "Tp2f", "Tp2g", "Tp2h"]
                    for key in eCoreKeys {
                        if let temp = try? smc.readTemperatureC(key: key), temp > 0 && temp < 150 {
                            eCoreTemps.append(temp)
                        }
                    }
                    
                    // Read PMU/SOC general temperatures as fallback
                    var pmcTemps: [Double] = []
                    let pmcKeys = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X"]
                    for key in pmcKeys {
                        if let temp = try? smc.readTemperatureC(key: key), temp > 0 && temp < 150 {
                            pmcTemps.append(temp)
                        }
                    }
                    
                    // Calculate CPU average (P-cores + E-cores, or PMC if no cores found)
                    var allCPUTemps = pCoreTemps + eCoreTemps
                    if allCPUTemps.isEmpty {
                        allCPUTemps = pmcTemps
                    }
                    let cpuAvg = allCPUTemps.isEmpty ? nil : allCPUTemps.reduce(0, +) / Double(allCPUTemps.count)
                    
                    // Calculate CPU hottest
                    let cpuHot = allCPUTemps.isEmpty ? nil : allCPUTemps.max()
                    
                    // Read GPU temperatures (Tg** for individual cores, TG** for averages)
                    var gpuCoreTemps: [Double] = []
                    var gpuAvgTemps: [Double] = []
                    
                    // Individual GPU core temps (Tg05, Tg0D, etc.)
                    let gpuCoreKeys = ["Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0b", "Tg0d", "Tg0f", "Tg0j", "Tg0l", "Tg0n", "Tg0p", "Tg0r", "Tg0t", "Tg0v", "Tg0x", "Tg0z"]
                    for key in gpuCoreKeys {
                        if let temp = try? smc.readTemperatureC(key: key), temp > 0 && temp < 150 {
                            gpuCoreTemps.append(temp)
                        }
                    }
                    
                    // GPU average temps (TG0D, TG0P, TGDD)
                    let gpuAvgKeys = ["TG0D", "TG0P", "TGDD", "TG0p"]
                    for key in gpuAvgKeys {
                        if let temp = try? smc.readTemperatureC(key: key), temp > 0 && temp < 150 {
                            gpuAvgTemps.append(temp)
                        }
                    }
                    
                    // Calculate GPU average: prefer GPU average keys, fall back to core average
                    let gpuAvg: Double?
                    if !gpuAvgTemps.isEmpty {
                        gpuAvg = gpuAvgTemps.reduce(0, +) / Double(gpuAvgTemps.count)
                    } else if !gpuCoreTemps.isEmpty {
                        gpuAvg = gpuCoreTemps.reduce(0, +) / Double(gpuCoreTemps.count)
                    } else {
                        gpuAvg = nil
                    }
                    
                    // Read Fan RPM - use same method as SMCSensorDebugView
                    var fanRPM: Int? = nil
                    do {
                        let rpm = try smc.currentRPM(fan: self.fanIndex)
                        fanRPM = rpm
                        print("[ViewModel] ✅ Successfully read Fan \(self.fanIndex) RPM: \(rpm)")
                    } catch {
                        print("[ViewModel] ❌ Failed to read Fan \(self.fanIndex) RPM: \(error)")
                    }
                    
                    // Update UI
                    self.cpuAvgC = cpuAvg
                    self.cpuHotC = cpuHot
                    self.gpuC = gpuAvg
                    self.lastTempC = cpuAvg
                    self.fanRPM = fanRPM
                    self.lastAppliedRPM = fanRPM
                    
                    // Update monitoring status
                    self.monitoringError = nil
                    
                    // Log detailed info on first run
                    if self.hidFirstRun {
                        self.hidFirstRun = false
                        print("[ViewModel] SMC Monitoring started:")
                        print("  - P-cores: \(pCoreTemps.count) sensors, avg: \(pCoreTemps.isEmpty ? "N/A" : String(format: "%.1f°C", pCoreTemps.reduce(0, +) / Double(pCoreTemps.count)))")
                        print("  - E-cores: \(eCoreTemps.count) sensors, avg: \(eCoreTemps.isEmpty ? "N/A" : String(format: "%.1f°C", eCoreTemps.reduce(0, +) / Double(eCoreTemps.count)))")
                        print("  - GPU cores: \(gpuCoreTemps.count) sensors")
                        print("  - CPU Avg: \(cpuAvg != nil ? String(format: "%.1f°C", cpuAvg!) : "N/A")")
                        print("  - CPU Hot: \(cpuHot != nil ? String(format: "%.1f°C", cpuHot!) : "N/A")")
                        print("  - GPU Avg: \(gpuAvg != nil ? String(format: "%.1f°C", gpuAvg!) : "N/A")")
                        print("  - Fan RPM: \(fanRPM != nil ? "\(fanRPM!) RPM" : "N/A")")
                    }
                }
            }
            
            // Store timer reference
            self.smcPollingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            
            // Fire immediately
            timer.fire()
        }
    }
}

