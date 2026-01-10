//
//  HIDSensorDebugView.swift
//  SMCController
//
//  HID 센서 목록을 실시간으로 표시하는 디버그 뷰

import SwiftUI

struct HIDSensorDebugView: View {
    @Environment(FanControlViewModel.self) private var viewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("HID Sensors (Apple Silicon)")
                    .font(.title2.weight(.semibold))
                
                if viewModel.hidSensorDetails.isEmpty {
                    Text("No HID sensors detected. Start monitoring to see sensors.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total sensors: \(viewModel.hidSensorDetails.count)")
                            .font(.headline)
                        
                        Divider()
                        
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(viewModel.hidSensorDetails.sorted(by: smartSort)) { sensor in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(sensor.name)
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.medium)
                                            .frame(width: 280, alignment: .leading)
                                        
                                        Spacer()
                                        
                                        Text(String(format: "%.1f°C", sensor.value))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundStyle(colorForTemperature(sensor.value))
                                            .frame(width: 70, alignment: .trailing)
                                    }
                                    
                                    HStack(spacing: 12) {
                                        Text("Location: \(sensor.location)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        
                                        Text("Page: 0x\(String(format: "%04X", sensor.usagePage))")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        
                                        Text("Usage: \(sensor.usage)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 8)
                                }
                                .padding(.vertical, 4)
                                
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 600, maxWidth: .infinity, alignment: .topLeading)
            .padding()
        }
    }
    
    private func colorForTemperature(_ temp: Double) -> Color {
        if temp > 80 {
            return .red
        } else if temp > 60 {
            return .orange
        } else {
            return .primary
        }
    }
    
    // Smart sorting: group by prefix, then sort by type (tdie/tdev), then by number
    private func smartSort(_ a: HIDSensorDetail, _ b: HIDSensorDetail) -> Bool {
        // Extract prefix (e.g., "PMU", "PMU2", "NAND")
        let prefixA = extractPrefix(a.name)
        let prefixB = extractPrefix(b.name)
        
        if prefixA != prefixB {
            // Different prefixes: sort alphabetically
            return prefixA < prefixB
        }
        
        // Same prefix: extract type (tdie/tdev/other) and number
        let (typeA, numA) = extractTypeAndNumber(a.name)
        let (typeB, numB) = extractTypeAndNumber(b.name)
        
        if typeA != typeB {
            // tdie comes before tdev
            return typeA < typeB
        }
        
        // Same type: sort by number
        return numA < numB
    }
    
    private func extractPrefix(_ name: String) -> String {
        // Handle special cases first
        if name.hasPrefix("NAND") { return "NAND" }
        if name.hasPrefix("PMU2") { return "PMU2" }
        if name.hasPrefix("PMU") { return "PMU" }
        if name.hasPrefix("GPU") { return "GPU" }
        if name.hasPrefix("SOC") { return "SOC" }
        if name.hasPrefix("pACC") { return "pACC" }
        if name.hasPrefix("eACC") { return "eACC" }
        
        // Default: everything before first space
        return String(name.split(separator: " ").first ?? "")
    }
    
    private func extractTypeAndNumber(_ name: String) -> (type: String, number: Int) {
        // Extract tdie/tdev and number
        if name.contains("tdie") {
            let num = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .last ?? 0
            return ("tdie", num)
        } else if name.contains("tdev") {
            let num = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .last ?? 0
            return ("tdev", num)
        } else if name.contains("tcal") {
            return ("tcal", 0)
        } else {
            // Other types: extract number if any
            let num = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .last ?? 0
            return ("other", num)
        }
    }
}

#Preview {
    HIDSensorDebugView()
        .environment(FanControlViewModel())
}
