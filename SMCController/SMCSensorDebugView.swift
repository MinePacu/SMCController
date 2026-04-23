//
//  SMCSensorDebugView.swift
//  SMCController
//
//  SMC 센서 목록을 실시간으로 표시하는 디버그 뷰

import SwiftUI

struct SMCSensorDebugView: View {
    @Environment(FanControlViewModel.self) private var viewModel
    @State private var sensors: [SMCSensorData] = []
    @State private var isMonitoring = false
    @State private var errorMessage: String?
    @State private var pollingTask: Task<Void, Never>?
    @State private var powerSample: DaemonClient.PowerMetrics?
    @State private var isPowerSampling = false
    @State private var powerSampleError: String?
    @State private var lastPowerSampleAt: Date?
    @State private var groupedIndices: [String: [Int]] = [:]
    
    private let pollInterval: TimeInterval = 2.0
    private let powerSampleInterval: TimeInterval = 2.0
    @State private var powerStreamActive = false
    
    // Fan control debug
    @State private var fanControlEnabled = false
    @State private var targetRPM: String = "2000"
    @State private var selectedFanIndex = 0
    @State private var fanControlMessage: String?
    @State private var isManualMode = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("SMC Sensors")
                        .font(.title2.weight(.semibold))
                    
                    Spacer()
                    
                    Button(isMonitoring ? "Stop" : "Start Monitoring") {
                        if isMonitoring {
                            stopMonitoring()
                        } else {
                            startMonitoring()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                // Fan Control Debug Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Fan Control Debug", systemImage: "fan.fill")
                                .font(.headline)
                            
                            Spacer()
                            
                            // Manual Mode Toggle
                            Toggle("Manual Mode", isOn: $isManualMode)
                                .toggleStyle(.switch)
                                .onChange(of: isManualMode) { _, newValue in
                                    setManualMode(newValue)
                                }
                        }
                        
                        Divider()
                        
                        HStack(spacing: 16) {
                            // Fan Index Picker
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Fan Index")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Fan", selection: $selectedFanIndex) {
                                    ForEach(0..<4) { index in
                                        Text("Fan \(index)").tag(index)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                            }
                            
                            // Target RPM Input
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Target RPM")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("RPM", text: $targetRPM)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .onChange(of: targetRPM) { _, newValue in
                                        // Only allow digits
                                        let filtered = newValue.filter { $0.isNumber }
                                        if filtered != newValue {
                                            targetRPM = filtered
                                        }
                                    }
                                    .onSubmit {
                                        if isManualMode {
                                            setFanRPM()
                                        }
                                    }
                            }
                            
                            // Set Button
                            Button("Set RPM") {
                                setFanRPM()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isManualMode)
                            
                            // Reset to Auto Button
                            Button("Reset to Auto") {
                                isManualMode = false
                                setManualMode(false)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!isManualMode)
                            
                            Spacer()
                        }
                        
                        // Show current fan info
                        if let fanSensor = sensors.first(where: { $0.key == "F\(selectedFanIndex)Ac" }) {
                            HStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Current RPM")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(fanSensor.formattedValue)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.blue)
                                }
                                
                                if let minSensor = sensors.first(where: { $0.key == "F\(selectedFanIndex)Mn" }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Min RPM")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(minSensor.formattedValue)
                                            .font(.system(.caption, design: .monospaced))
                                    }
                                }
                                
                                if let maxSensor = sensors.first(where: { $0.key == "F\(selectedFanIndex)Mx" }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Max RPM")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(maxSensor.formattedValue)
                                            .font(.system(.caption, design: .monospaced))
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        // Status message
                        if let message = fanControlMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(message.contains("✅") ? .green : (message.contains("❌") ? .red : .orange))
                        }
                        
                        // Warning
                        if isManualMode {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Manual mode overrides system fan control. Use with caution!")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(8)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                
                if sensors.isEmpty {
                    Text("No SMC sensors detected. Click 'Start Monitoring' to scan for sensors.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Total sensors: \(sensors.count)")
                                .font(.headline)
                            
                            Spacer()
                            
                            // Show GPU core count
                            let gpuCores = sensors.filter { $0.key.hasPrefix("Tg0") || $0.key.hasPrefix("Tg1") }
                            if !gpuCores.isEmpty {
                                Text("GPU Cores: \(gpuCores.count)")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        Divider()
                        
                        // CPU Temperature Summary
                        let cpuSummary = calculateCPUSummary()
                        if cpuSummary.hasCPUData {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("📊 CPU Temperature Summary")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                HStack(spacing: 20) {
                                    if let pCoreAvg = cpuSummary.pCoreAvg {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("P-Core Avg")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.1f°C", pCoreAvg))
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(colorForTemperature(pCoreAvg))
                                        }
                                    }
                                    
                                    if let eCoreAvg = cpuSummary.eCoreAvg {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("E-Core Avg")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.1f°C", eCoreAvg))
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(colorForTemperature(eCoreAvg))
                                        }
                                    }
                                    
                                    if let packageAvg = cpuSummary.packageAvg {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Package Avg")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.1f°C", packageAvg))
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(colorForTemperature(packageAvg))
                                        }
                                    }
                                    
                                    if let hottest = cpuSummary.hottestTemp {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Hottest CPU")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.1f°C", hottest))
                                                .font(.system(.body, design: .monospaced))
                                                .fontWeight(.bold)
                                                .foregroundStyle(colorForTemperature(hottest))
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.bottom, 8)
                        }
                        
                        // Power Summary
                        let cpuPower = powerValue(keys: ["PCPC", "PC0C", "PCPU"]) ?? powerSample?.cpu
                        let gpuPower = powerValue(keys: ["PCPG", "PG0C", "PG0R"]) ?? powerSample?.gpu
                        let dcInPower = powerValue(keys: ["PDTR"]) ?? powerSample?.dc
                        if cpuPower != nil || gpuPower != nil || dcInPower != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("⚡ Power")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                HStack(spacing: 20) {
                                    if let cpu = cpuPower {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("CPU Power")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.2f W", cpu))
                                                .font(.system(.body, design: .monospaced))
                                        }
                                    }
                                    
                                    if let gpu = gpuPower {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("GPU Power")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.2f W", gpu))
                                                .font(.system(.body, design: .monospaced))
                                        }
                                    }
                                    
                                    if let dc = dcInPower {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("DC In")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.2f W", dc))
                                                .font(.system(.body, design: .monospaced))
                                        }
                                    }
                                }
                                .padding(.vertical, 4)

                                HStack(spacing: 12) {
                                    if let err = powerSampleError {
                                        Text(err)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.bottom, 8)
                        }
                        
                        Divider()
                        
                        LazyVStack(alignment: .leading, spacing: 12) {
                            let categoryOrder = [
                                "💨 Fans",
                                "🔥 P-Core Clusters",
                                "⚡ E-Core Clusters",
                                "🧠 PMU/SOC",
                                "🎮 GPU Cores (Individual)",
                                "🖥️ GPU (Average)",
                                "⚡ Power",
                                "⚙️ Intel CPU",
                                "🌡️ Other"
                            ]
                            
                            ForEach(categoryOrder, id: \.self) { category in
                                if let indices = groupedIndices[category]?.filter({ $0 < sensors.count }), !indices.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        // Category header with count
                                        HStack {
                                            Text(category)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            
                                            Text("(\(indices.count))")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.top, 8)
                                        
                                        Divider()
                                        
                                        // Sensors in this category
                                        ForEach(indices, id: \.self) { idx in
                                            if idx < sensors.count {
                                                let sensor = sensors[idx]
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack {
                                                        Text(sensor.key)
                                                            .font(.system(.body, design: .monospaced))
                                                            .fontWeight(.medium)
                                                            .frame(width: 80, alignment: .leading)
                                                        
                                                        Text(sensor.name)
                                                            .font(.system(.caption, design: .default))
                                                            .foregroundStyle(.secondary)
                                                            .frame(width: 200, alignment: .leading)
                                                        
                                                        Spacer()
                                                        
                                                        Text(sensor.formattedValue)
                                                            .font(.system(.body, design: .monospaced))
                                                            .foregroundStyle(colorForSensor(sensor))
                                                            .frame(width: 100, alignment: .trailing)
                                                        
                                                        Text(sensor.type)
                                                            .font(.system(.caption, design: .monospaced))
                                                            .foregroundStyle(.tertiary)
                                                            .frame(width: 60, alignment: .leading)
                                                    }
                                                }
                                                .padding(.vertical, 2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            stopMonitoring()
        }
    }
    
    private func startMonitoring() {
        isMonitoring = true
        errorMessage = nil
        
        // Scan for common SMC sensors
        scanSensors()
        
        startPollingLoop()
        startPowerStream()
    }
    
    private func stopMonitoring() {
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        lastPowerSampleAt = nil
        DaemonClient.shared.stopPowerStream()
        powerStreamActive = false
        
        // Auto-disable manual mode when stopping monitoring
        if isManualMode {
            isManualMode = false
            setManualMode(false)
        }
    }
    
    private func startPowerStream() {
        DaemonClient.shared.startPowerStream { metrics in
            self.powerSample = metrics
            self.lastPowerSampleAt = Date()
            self.powerStreamActive = true
            self.powerSampleError = nil
        } onError: {
            self.powerStreamActive = false
            // Restart after a short delay to keep push updates alive
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if isMonitoring {
                    startPowerStream()
                }
            }
        }
    }
    
    private func scanSensors() {
        print("[SMCSensorDebugView] 🔍 Scanning sensors...")
        var detectedSensors: [SMCSensorData] = []
        
        // Common temperature sensors
        let tempKeys = [
            ("TC0P", "CPU Proximity"),
            ("TC0D", "CPU Die"),
            ("TC0E", "CPU Core"),
            ("TC0F", "CPU Core"),
            ("TG0P", "GPU Proximity"),
            ("TG0D", "GPU Die"),
            ("Ts0P", "Palm Rest"),
            ("Tm0P", "Memory Proximity"),
            ("TB0T", "Battery"),
            ("TN0P", "Northbridge"),
            ("TH0P", "Hard Drive"),
        ]
        
        // M-series Performance Core temperatures
        let mSeriesPCoreKeys = [
            ("Tp0a", "P-Core 0"),
            ("Tp0b", "P-Core 1"),
            ("Tp0c", "P-Core 2"),
            ("Tp0d", "P-Core 3"),
            ("Tp1a", "P-Core 4"),
            ("Tp1b", "P-Core 5"),
            ("Tp1c", "P-Core 6"),
            ("Tp1d", "P-Core 7"),
        ]
        
        // M-series Efficiency Core temperatures
        let mSeriesECoreKeys = [
            ("Tp0e", "E-Core 0"),
            ("Tp0f", "E-Core 1"),
            ("Tp0g", "E-Core 2"),
            ("Tp0h", "E-Core 3"),
            ("Tp1e", "E-Core 4"),
            ("Tp1f", "E-Core 5"),
            ("Tp1g", "E-Core 6"),
            ("Tp1h", "E-Core 7"),
            ("Tp2e", "E-Core 8"),
            ("Tp2f", "E-Core 9"),
            ("Tp2g", "E-Core 10"),
            ("Tp2h", "E-Core 11"),
        ]
        
        // M-series PMU/SOC general temperatures
        let mSeriesKeys = [
            ("Tp09", "PMU Die 9"),
            ("Tp0T", "PMU Die T"),
            ("Tp01", "PMU Die 1"),
            ("Tp05", "PMU Die 5"),
            ("Tp0D", "PMU Die D"),
            ("Tp0H", "PMU Die H"),
            ("Tp0L", "PMU Die L"),
            ("Tp0P", "PMU Die P"),
            ("Tp0X", "PMU Die X"),
            ("Tp0j", "PMU Die j"),
            ("Tp0n", "PMU Die n"),
            ("Tp0r", "PMU Die r"),
            ("Tp0t", "PMU Die t"),
            ("Tp0x", "PMU Die x"),
        ]
        
        // M-series GPU Core temperatures (M4: 8 cores, M4 Pro: 16-20 cores)
        // Known M4 base keys: Tg0D, Tg0L, Tg0d, Tg0j, Tg0n
        let mSeriesGPUCoreKeys = [
            // Confirmed M4 base keys
            ("Tg0D", "GPU Core"),
            ("Tg0L", "GPU Core"),
            ("Tg0d", "GPU Core"),
            ("Tg0j", "GPU Core"),
            ("Tg0n", "GPU Core"),
            // Pattern-based likely keys for remaining 3 cores
            ("Tg05", "GPU Core"),
            ("Tg0T", "GPU Core"),
            ("Tg0b", "GPU Core"),
            ("Tg0f", "GPU Core"),
            ("Tg0r", "GPU Core"),
            ("Tg0v", "GPU Core"),
            ("Tg0z", "GPU Core"),
            // Additional uppercase possibilities
            ("Tg0A", "GPU Core"),
            ("Tg0B", "GPU Core"),
            ("Tg0C", "GPU Core"),
            ("Tg0E", "GPU Core"),
            ("Tg0F", "GPU Core"),
            ("Tg0G", "GPU Core"),
            ("Tg0H", "GPU Core"),
            ("Tg0I", "GPU Core"),
            ("Tg0J", "GPU Core"),
            ("Tg0K", "GPU Core"),
            ("Tg0M", "GPU Core"),
            ("Tg0N", "GPU Core"),
            ("Tg0O", "GPU Core"),
            ("Tg0P", "GPU Core"),
            ("Tg0Q", "GPU Core"),
            ("Tg0R", "GPU Core"),
            ("Tg0S", "GPU Core"),
            ("Tg0U", "GPU Core"),
            ("Tg0V", "GPU Core"),
            ("Tg0W", "GPU Core"),
            ("Tg0X", "GPU Core"),
            // Additional lowercase possibilities
            ("Tg0a", "GPU Core"),
            ("Tg0c", "GPU Core"),
            ("Tg0e", "GPU Core"),
            ("Tg0g", "GPU Core"),
            ("Tg0h", "GPU Core"),
            ("Tg0i", "GPU Core"),
            ("Tg0k", "GPU Core"),
            ("Tg0l", "GPU Core"),
            ("Tg0m", "GPU Core"),
            ("Tg0o", "GPU Core"),
            ("Tg0p", "GPU Core"),
            ("Tg0q", "GPU Core"),
            ("Tg0s", "GPU Core"),
            ("Tg0t", "GPU Core"),
            ("Tg0u", "GPU Core"),
            ("Tg0w", "GPU Core"),
            ("Tg0x", "GPU Core"),
            ("Tg0y", "GPU Core"),
            // Pro/Max models
            ("Tg1a", "GPU Core"),
            ("Tg1b", "GPU Core"),
            ("Tg1d", "GPU Core"),
            ("Tg1f", "GPU Core"),
            ("Tg1j", "GPU Core"),
            ("Tg1n", "GPU Core"),
        ]
        
        // M-series GPU general keys
        let mSeriesGPUKeys = [
            ("TG0D", "GPU Die Average"),
            ("TG0P", "GPU Proximity"),
            ("TGDD", "GPU Die Digital"),
            ("TG0p", "GPU Package"),
        ]
        
        // Fan keys
        let fanKeys = [
            ("FNum", "Fan Count"),
            ("F0Ac", "Fan 0 Actual RPM"),
            ("F0Mn", "Fan 0 Min RPM"),
            ("F0Mx", "Fan 0 Max RPM"),
            ("F0Tg", "Fan 0 Target RPM"),
            ("F1Ac", "Fan 1 Actual RPM"),
            ("F1Mn", "Fan 1 Min RPM"),
            ("F1Mx", "Fan 1 Max RPM"),
            ("F1Tg", "Fan 1 Target RPM"),
        ]
        
        // Power keys
        let powerKeys = [
            ("PCPC", "CPU Power"),
            ("PCPG", "GPU Power"),
            ("PDTR", "DC In Total"),
        ]
        
        let allKeys = tempKeys + mSeriesPCoreKeys + mSeriesECoreKeys + mSeriesKeys + mSeriesGPUCoreKeys + mSeriesGPUKeys + fanKeys + powerKeys
        
        print("[SMCSensorDebugView] Scanning \(allKeys.count) keys...")
        for (key, name) in allKeys {
            if let sensorData = readSMCKey(key, name: name) {
                print("[SMCSensorDebugView] ✅ Found: \(key) = \(sensorData.formattedValue)")
                detectedSensors.append(sensorData)
            }
        }
        
        // Renumber CPU cores based on actual system configuration
        renumberCPUCores(&detectedSensors)
        
        // Renumber GPU cores sequentially
        renumberGPUCores(&detectedSensors)
        
        print("[SMCSensorDebugView] ✅ Found \(detectedSensors.count) sensors")
        sensors = detectedSensors
        groupedIndices = buildCategoryIndices(for: detectedSensors)
        
        if sensors.isEmpty {
            errorMessage = "No SMC sensors found. SMC may not be accessible."
        } else {
            errorMessage = nil
        }
    }
    
    private func renumberGPUCores(_ sensors: inout [SMCSensorData]) {
        // Get actual GPU core count from IORegistry
        let gpuCoreCount = getGPUCoreCount()
        
        // Find all GPU core sensors (Tg0x, Tg1x)
        var gpuCores: [(index: Int, key: String, value: Double)] = []
        for (index, sensor) in sensors.enumerated() {
            if sensor.key.hasPrefix("Tg0") || sensor.key.hasPrefix("Tg1") {
                gpuCores.append((index: index, key: sensor.key, value: sensor.value))
            }
        }
        
        // Sort by key to get consistent ordering
        gpuCores.sort { $0.key < $1.key }
        
        // Only keep the first N cores matching the actual GPU core count
        let validCoreCount = min(gpuCoreCount, gpuCores.count)
        // Remove invalid sensors (cores beyond actual count)
        let invalidIndices = Set(gpuCores.dropFirst(validCoreCount).map { $0.index })
        sensors = sensors.enumerated().filter { !invalidIndices.contains($0.offset) }.map { $0.element }
        
        // Re-find valid GPU cores after filtering
        var validGPUCores: [(index: Int, key: String)] = []
        for (index, sensor) in sensors.enumerated() {
            if sensor.key.hasPrefix("Tg0") || sensor.key.hasPrefix("Tg1") {
                validGPUCores.append((index: index, key: sensor.key))
            }
        }
        
        // Sort by key
        validGPUCores.sort { $0.key < $1.key }
        
        // Renumber sequentially
        for (coreNum, item) in validGPUCores.enumerated() {
            let newName = "GPU Core \(coreNum + 1)"
            sensors[item.index] = SMCSensorData(
                key: sensors[item.index].key,
                name: newName,
                value: sensors[item.index].value,
                formattedValue: sensors[item.index].formattedValue,
                type: sensors[item.index].type,
                dataSize: sensors[item.index].dataSize
            )
        }
        
        if validGPUCores.count > 0 {
            print("[SMCSensorDebugView] 🎮 GPU: \(validGPUCores.count)/\(gpuCoreCount) cores")
        }
    }
    
    private func renumberCPUCores(_ sensors: inout [SMCSensorData]) {
        let (eCoreCnt, pCoreCnt) = getCPUCoreCount()
        
        // M4 uses cluster-level temperature sensors, not per-core
        // E-cores: Tp0e, Tp0f (2 sensors for 4 cores)
        // P-cores: Tp0a, Tp0b, Tp0c, Tp0d (4 sensors for 6 cores)
        
        // Find E-core cluster sensors
        var eCores: [(index: Int, key: String)] = []
        for (index, sensor) in sensors.enumerated() {
            let key = sensor.key
            if key.hasPrefix("Tp") && key.count == 4 {
                let lastChar = String(key.suffix(1))
                if ["e", "f", "g", "h"].contains(lastChar) {
                    eCores.append((index: index, key: key))
                }
            }
        }
        
        // Find P-core cluster sensors
        var pCores: [(index: Int, key: String)] = []
        for (index, sensor) in sensors.enumerated() {
            let key = sensor.key
            if key.hasPrefix("Tp") && key.count == 4 {
                let lastChar = String(key.suffix(1))
                if ["a", "b", "c", "d"].contains(lastChar) {
                    pCores.append((index: index, key: key))
                }
            }
        }
        
        // Sort by key
        eCores.sort { $0.key < $1.key }
        pCores.sort { $0.key < $1.key }
        
        // If no specific core keys found, skip filtering
        if eCores.isEmpty && pCores.isEmpty {
            return
        }
        
        // Don't filter CPU cores - M4 uses cluster sensors, not per-core sensors
        // Just rename them for clarity
        
        // Renumber E-core cluster sensors
        for (sensorNum, item) in eCores.enumerated() {
            let clusterNum = sensorNum + 1
            sensors[item.index] = SMCSensorData(
                key: sensors[item.index].key,
                name: "E-Core Cluster \(clusterNum)",
                value: sensors[item.index].value,
                formattedValue: sensors[item.index].formattedValue,
                type: sensors[item.index].type,
                dataSize: sensors[item.index].dataSize
            )
        }
        
        // Renumber P-core cluster sensors
        for (sensorNum, item) in pCores.enumerated() {
            let clusterNum = sensorNum + 1
            sensors[item.index] = SMCSensorData(
                key: sensors[item.index].key,
                name: "P-Core Cluster \(clusterNum)",
                value: sensors[item.index].value,
                formattedValue: sensors[item.index].formattedValue,
                type: sensors[item.index].type,
                dataSize: sensors[item.index].dataSize
            )
        }
        
        if eCores.count > 0 || pCores.count > 0 {
            print("[SMCSensorDebugView] 🧠 CPU: \(eCoreCnt)E/\(pCoreCnt)P cores, \(eCores.count)E/\(pCores.count)P clusters")
        }
    }
    
    private func getCPUCoreCount() -> (eCore: Int, pCore: Int) {
        var eCore = 4  // Default E-core count
        var pCore = 4  // Default P-core count
        
        // perflevel0 = E-cores (Efficiency)
        var perflevel0Size = 0
        var perflevel0Value: Int32 = 0
        perflevel0Size = MemoryLayout<Int32>.size
        
        if sysctlbyname("hw.perflevel0.physicalcpu", &perflevel0Value, &perflevel0Size, nil, 0) == 0 {
            eCore = Int(perflevel0Value)
        }
        
        // perflevel1 = P-cores (Performance)
        var perflevel1Size = 0
        var perflevel1Value: Int32 = 0
        perflevel1Size = MemoryLayout<Int32>.size
        
        if sysctlbyname("hw.perflevel1.physicalcpu", &perflevel1Value, &perflevel1Size, nil, 0) == 0 {
            pCore = Int(perflevel1Value)
        }
        
        return (eCore, pCore)
    }
    
    private func getGPUCoreCount() -> Int {
        // Query IORegistry for GPU core count
        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0
        
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            print("[SMCSensorDebugView] ⚠️ Failed to get GPU service, defaulting to 10 cores")
            return 10
        }
        
        defer { IOObjectRelease(iterator) }
        
        var coreCount = 10 // Default for M4 base
        
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            // Try to get core count from "gpu-core-count" property
            if let coreCountRef = IORegistryEntryCreateCFProperty(
                service,
                "gpu-core-count" as CFString,
                kCFAllocatorDefault,
                0
            ) {
                if let count = coreCountRef.takeRetainedValue() as? Int {
                    coreCount = count
                    print("[SMCSensorDebugView] 📊 GPU core count from IORegistry: \(count)")
                    break
                }
            }
        }
        
        return coreCount
    }
    
    private func updateSensorValues() {
        let snapshot = sensors
        var updates: [(Int, SMCSensorData)] = []
        for (idx, sensor) in snapshot.enumerated() {
            let existingName = sensor.name
            if let updated = readSMCKey(sensor.key, name: existingName) {
                updates.append((idx, updated))
            }
        }
        
        if !updates.isEmpty {
            for (idx, updated) in updates {
                if idx < sensors.count {
                    sensors[idx] = updated
                }
            }
        }
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task.detached { [self] in
            while !Task.isCancelled {
                let snapshot = await MainActor.run { self.sensors }
                
                var updates: [(Int, SMCSensorData)] = []
                for (idx, sensor) in snapshot.enumerated() {
                    if let updated = await MainActor.run(body: { readSMCKey(sensor.key, name: sensor.name) }) {
                        updates.append((idx, updated))
                    }
                }
                
                if !updates.isEmpty {
                    let updatesToApply = updates
                    await MainActor.run {
                        for (idx, updated) in updatesToApply where idx < sensors.count {
                            sensors[idx] = updated
                        }
                    }
                }
                
                let ns = UInt64(pollInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }
    
    private func readSMCKey(_ key: String, name: String) -> SMCSensorData? {
        // Use shared SMC instance from ViewModel, initialize if needed
        if viewModel.smc == nil {
            do {
                viewModel.smc = try SMCService()
            } catch {
                print("[SMCSensorDebugView] ❌ Failed to initialize SMC: \(error)")
                return nil
            }
        }
        
        guard let smc = viewModel.smc, let conn = smc.connection else {
            print("[SMCSensorDebugView] ❌ SMC not available")
            return nil
        }
        
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        
        let result = smc_read_key_info(conn, key, &dataSize, &dataType)
        
        if result == 0 {
            // Successfully read key info
            let typeStr = typeCodeToString(dataType)
            
            // Read actual value
            var buffer = [UInt8](repeating: 0, count: 32)
            var actualDataSize: UInt32 = 0
            var actualDataType: UInt32 = 0
            let readResult = smc_read_key(conn, key, &buffer, dataSize, &actualDataSize, &actualDataType)
            
            if readResult > 0 {  // smc_read_key returns bytes read, not error code
                let value = decodeValue(buffer, type: dataType, size: dataSize)
                let formattedValue = formatValue(value, type: typeStr, key: key)
                
                return SMCSensorData(
                    key: key,
                    name: name,
                    value: value,
                    formattedValue: formattedValue,
                    type: typeStr,
                    dataSize: Int(dataSize)
                )
            }
        }
        
        return nil
    }
    
    private func typeCodeToString(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
    
    private func powerValue(keys: [String]) -> Double? {
        for key in keys {
            if let val = sensors.first(where: { $0.key == key })?.value {
                return val
            }
        }
        return nil
    }

    private func samplePowermetrics() {
        isPowerSampling = true
        powerSampleError = nil
        Task.detached {
            let sample = await DaemonClient.shared.fetchPowerMetrics()
            await MainActor.run {
                self.powerSample = sample
                self.isPowerSampling = false
                self.lastPowerSampleAt = Date()
                self.powerSampleError = sample == nil ? "power read failed" : nil
            }
        }
    }

    private func samplePowermetricsIfNeeded() {
        // Align with UI poll cadence (2s) but avoid overlapping executions
        guard !isPowerSampling else { return }
        let now = Date()
        if let last = lastPowerSampleAt, now.timeIntervalSince(last) < powerSampleInterval {
            return
        }
        samplePowermetrics()
    }

    private func formatRelative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func decodeValue(_ bytes: [UInt8], type: UInt32, size: UInt32) -> Double {
        let typeStr = typeCodeToString(type)
        
        switch typeStr {
        case "fpe2": // Fixed point e2
            if size >= 2 {
                let value = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
                return Double(Int16(bitPattern: value)) / 4.0
            }
            
        case "sp78", "sp87": // Signed fixed point
            if size >= 2 {
                let value = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
                return Double(Int16(bitPattern: value)) / 256.0
            }
            
        case "ui8 ": // Unsigned 8-bit
            return Double(bytes[0])
            
        case "ui16": // Unsigned 16-bit
            if size >= 2 {
                let value = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
                return Double(value)
            }
            
        case "ui32": // Unsigned 32-bit
            if size >= 4 {
                let value = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
                           (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
                return Double(value)
            }
            
        case "flt ": // Float (little-endian)
            if size >= 4 {
                // SMC returns bytes in little-endian order for floats
                let value = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) |
                           (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
                return Double(Float(bitPattern: value))
            }
            
        default:
            break
        }
        
        return 0.0
    }
    
    private func formatValue(_ value: Double, type: String, key: String = "") -> String {
        // Temperature sensors
        if type.hasPrefix("sp") || type == "fpe2" {
            return String(format: "%.1f°C", value)
        }
        
        // Fan RPM sensors (key starts with F and contains Ac, Mn, Mx, Tg)
        if key.hasPrefix("F") && (key.contains("Ac") || key.contains("Mn") || key.contains("Mx") || key.contains("Tg")) {
            return String(format: "%.0f RPM", value)
        }
        
        // Small integers (like fan count)
        if type.hasPrefix("ui") && value < 10 {
            return String(format: "%.0f", value)
        }
        
        // Power values (flt type for power)
        if type == "flt " && (key.hasPrefix("PC") || key.hasPrefix("PD")) {
            return String(format: "%.2f W", value)
        }
        
        // Other flt values
        if type == "flt " {
            return String(format: "%.2f", value)
        }
        
        // Large unsigned integers
        if type.hasPrefix("ui") {
            return String(format: "%.0f", value)
        }
        
        return String(format: "%.2f", value)
    }
    
    private func colorForSensor(_ sensor: SMCSensorData) -> Color {
        // Temperature sensors
        if sensor.type.hasPrefix("sp") || sensor.type == "fpe2" {
            return colorForTemperature(sensor.value)
        }
        return .primary
    }
    
    private func colorForTemperature(_ temp: Double) -> Color {
        if temp > 80 {
            return .red
        } else if temp > 60 {
            return .orange
        }
        return .green
    }
    
    private func calculateCPUSummary() -> CPUSummary {
        var pCoreTemps: [Double] = []
        var eCoreTemps: [Double] = []
        var allCPUTemps: [Double] = []
        
        for sensor in sensors {
            let key = sensor.key
            
            // P-Core clusters: Tp0a-d
            if key.hasPrefix("Tp0") && ["a", "b", "c", "d"].contains(String(key.suffix(1))) {
                pCoreTemps.append(sensor.value)
                allCPUTemps.append(sensor.value)
            }
            // E-Core clusters: Tp0e-f
            else if key.hasPrefix("Tp0") && ["e", "f"].contains(String(key.suffix(1))) {
                eCoreTemps.append(sensor.value)
                allCPUTemps.append(sensor.value)
            }
        }
        
        let pCoreAvg = pCoreTemps.isEmpty ? nil : pCoreTemps.reduce(0, +) / Double(pCoreTemps.count)
        let eCoreAvg = eCoreTemps.isEmpty ? nil : eCoreTemps.reduce(0, +) / Double(eCoreTemps.count)
        let packageAvg = allCPUTemps.isEmpty ? nil : allCPUTemps.reduce(0, +) / Double(allCPUTemps.count)
        let hottestTemp = allCPUTemps.isEmpty ? nil : allCPUTemps.max()
        
        return CPUSummary(
            pCoreAvg: pCoreAvg,
            eCoreAvg: eCoreAvg,
            packageAvg: packageAvg,
            hottestTemp: hottestTemp,
            hasCPUData: !allCPUTemps.isEmpty
        )
    }
    
    struct CPUSummary {
        let pCoreAvg: Double?
        let eCoreAvg: Double?
        let packageAvg: Double?
        let hottestTemp: Double?
        let hasCPUData: Bool
    }
    
    private func buildCategoryIndices(for sensors: [SMCSensorData]) -> [String: [Int]] {
        var grouped: [String: [Int]] = [
            "🔥 P-Core Clusters": [],
            "⚡ E-Core Clusters": [],
            "🎮 GPU Cores (Individual)": [],
            "🖥️ GPU (Average)": [],
            "🧠 PMU/SOC": [],
            "💨 Fans": [],
            "⚙️ Intel CPU": [],
            "⚡ Power": [],
            "🌡️ Other": []
        ]

        for (idx, sensor) in sensors.enumerated() {
            let category = categoryForKey(sensor.key)
            grouped[category, default: []].append(idx)
        }

        var result: [String: [Int]] = [:]
        for (category, indices) in grouped {
            guard !indices.isEmpty else { continue }
            if category == "🎮 GPU Cores (Individual)" {
                result[category] = indices.sorted { sensors[$0].key < sensors[$1].key }
            } else {
                result[category] = indices
            }
        }
        return result
    }

    private func categoryForKey(_ key: String) -> String {
        if key.hasPrefix("Tp0") && ["a", "b", "c", "d"].contains(String(key.suffix(1))) {
            return "🔥 P-Core Clusters"
        } else if key.hasPrefix("Tp1") && ["a", "b", "c", "d"].contains(String(key.suffix(1))) {
            return "🔥 P-Core Clusters"
        } else if key.hasPrefix("Tp0") && ["e", "f", "g", "h"].contains(String(key.suffix(1))) {
            return "⚡ E-Core Clusters"
        } else if key.hasPrefix("Tp1") && ["e", "f", "g", "h"].contains(String(key.suffix(1))) {
            return "⚡ E-Core Clusters"
        } else if key.hasPrefix("Tp2") && ["e", "f", "g", "h"].contains(String(key.suffix(1))) {
            return "⚡ E-Core Clusters"
        } else if key.hasPrefix("Tg0") || key.hasPrefix("Tg1") {
            return "🎮 GPU Cores (Individual)"
        } else if key.hasPrefix("TG") {
            return "🖥️ GPU (Average)"
        } else if key.hasPrefix("Tp") {
            return "🧠 PMU/SOC"
        } else if key.hasPrefix("F") {
            return "💨 Fans"
        } else if key.hasPrefix("TC") {
            return "⚙️ Intel CPU"
        } else if key.hasPrefix("PC") || key.hasPrefix("PD") {
            return "⚡ Power"
        }
        return "🌡️ Other"
    }
    
    // MARK: - Fan Control Debug Functions
    
    private func setManualMode(_ enabled: Bool) {
        fanControlMessage = nil
        
        // Use ViewModel's shared SMC instance
        guard let smc = viewModel.smc else {
            fanControlMessage = "❌ SMC not available"
            return
        }
        
        print("[SMCSensorDebugView] Setting manual mode: \(enabled)")
        
        Task {
            do {
                try await smc.setManualMode(enabled)
                await MainActor.run {
                    fanControlMessage = "✅ Manual mode \(enabled ? "enabled" : "disabled")"
                    print("[SMCSensorDebugView] ✅ Manual mode set: \(enabled)")
                }
            } catch {
                // Manual mode may not be supported on Apple Silicon
                // This is OK - we can still try to write fan RPM directly
                print("[SMCSensorDebugView] ⚠️ Manual mode not supported (will try direct write): \(error)")
                await MainActor.run {
                    if enabled {
                        fanControlMessage = "⚠️ Manual mode not supported. Will try direct RPM write."
                    } else {
                        fanControlMessage = nil
                    }
                }
            }
        }
    }
    
    private func setFanRPM() {
        guard let rpm = Int(targetRPM) else {
            fanControlMessage = "❌ Invalid RPM value"
            return
        }
        
        // Validate RPM range
        if let minSensor = sensors.first(where: { $0.key == "F\(selectedFanIndex)Mn" }),
           let maxSensor = sensors.first(where: { $0.key == "F\(selectedFanIndex)Mx" }) {
            let minRPM = Int(minSensor.value)
            let maxRPM = Int(maxSensor.value)
            
            if rpm < minRPM || rpm > maxRPM {
                fanControlMessage = "⚠️ RPM out of range (\(minRPM)-\(maxRPM))"
                return
            }
        }
        
        // Use ViewModel's shared SMC instance
        guard let smc = viewModel.smc else {
            fanControlMessage = "❌ SMC not available"
            return
        }
        
        print("[SMCSensorDebugView] Setting Fan \(selectedFanIndex) to \(rpm) RPM")
        
        // Show immediate feedback
        fanControlMessage = "⏳ Setting fan to \(rpm) RPM..."
        
        Task {
            do {
                // Try to set manual mode first (may fail on Apple Silicon)
                do {
                    try await smc.setManualMode(true)
                    print("[SMCSensorDebugView] ✅ Manual mode enabled")
                } catch {
                    print("[SMCSensorDebugView] ⚠️ Manual mode failed (trying direct write anyway): \(error)")
                }
                
                // Try to write RPM (may work even without manual mode)
                try await smc.setTargetRPM(fan: selectedFanIndex, rpm: rpm)
                
                // Verify target was written (immediate check)
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                let targetReadback = try smc.targetRPM(fan: selectedFanIndex)
                print("[SMCSensorDebugView] 📊 Target RPM (F\(selectedFanIndex)Tg): \(targetReadback)")
                
                if abs(targetReadback - rpm) > 10 {
                    await MainActor.run {
                        fanControlMessage = "⚠️ Target write may have failed: wrote \(rpm), read back \(targetReadback)"
                        updateSensorValues()
                    }
                    return
                }
                
                // Target set successfully - show status and wait for fan to respond
                await MainActor.run {
                    fanControlMessage = "✅ Target set to \(rpm) RPM. Fan is ramping..."
                    updateSensorValues()
                }
                
                // Wait for fan to reach target (fans take 2-5 seconds to ramp)
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3.0 seconds
                
                do {
                    let actualRPM = try smc.currentRPM(fan: selectedFanIndex)
                    print("[SMCSensorDebugView] 📊 Actual RPM (F\(selectedFanIndex)Ac): \(actualRPM)")
                    
                    await MainActor.run {
                        if abs(actualRPM - rpm) < 100 {
                            fanControlMessage = "✅ Fan reached target: \(actualRPM) RPM"
                        } else {
                            fanControlMessage = "⏳ Fan ramping: currently \(actualRPM) RPM (target \(rpm))"
                        }
                        updateSensorValues()
                    }
                } catch {
                    print("[SMCSensorDebugView] ⚠️ Could not read actual RPM: \(error)")
                    await MainActor.run {
                        fanControlMessage = "✅ Target set to \(rpm) RPM (actual RPM unreadable)"
                        updateSensorValues()
                    }
                }
            } catch {
                print("[SMCSensorDebugView] ⚠️ Error setting fan RPM: \(error)")
                await MainActor.run {
                    fanControlMessage = "❌ Failed to set fan RPM: \(error.localizedDescription)"
                    updateSensorValues()
                }
            }
        }
    }
}


struct SMCSensorData: Identifiable {
    let id = UUID()
    let key: String
    let name: String
    let value: Double
    let formattedValue: String
    let type: String
    let dataSize: Int
}

#Preview {
    SMCSensorDebugView()
        .environment(FanControlViewModel())
}
