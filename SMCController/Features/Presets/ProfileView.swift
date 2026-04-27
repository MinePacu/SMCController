//
//  ProfileView.swift
//  SMCController
//

import SwiftUI

struct ProfileView: View {
    @Environment(FanControlViewModel.self) private var viewModel
    @State private var presetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                currentSettingsCard
                savePresetCard
                presetsCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Profiles & Presets")
                .font(.largeTitle.weight(.semibold))
            Text("Current settings are saved automatically. Save named presets here to quickly switch fan curves and PID tuning.")
                .foregroundStyle(.secondary)
        }
    }

    private var currentSettingsCard: some View {
        GroupBox("Current Settings") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Sensor") {
                    Text(viewModel.sensorKey)
                }
                LabeledContent("Fan Index") {
                    Text("\(viewModel.fanIndex)")
                }
                LabeledContent("Curve Points") {
                    Text("\(viewModel.curve.count)")
                }
                LabeledContent("Temperature Range") {
                    Text("\(Int(viewModel.minC))-\(Int(viewModel.maxC)) °C")
                }
                LabeledContent("RPM Range") {
                    Text("\(Int(viewModel.minRPM))-\(Int(viewModel.maxRPM)) RPM")
                }
                LabeledContent("PID") {
                    Text(viewModel.usePID ? "Enabled" : "Disabled")
                }
                if viewModel.usePID {
                    LabeledContent("PID Gains") {
                        Text("Kp \(formatted(viewModel.kp))  Ki \(formatted(viewModel.ki))  Kd \(formatted(viewModel.kd))")
                            .monospacedDigit()
                    }
                }
                if !viewModel.extraSensorKeys.isEmpty {
                    LabeledContent("Extra Sensors") {
                        Text(viewModel.extraSensorKeys.joined(separator: ", "))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }

                HStack {
                    Button("Save Current Settings") {
                        viewModel.saveCurrentSettingsSnapshot()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private var savePresetCard: some View {
        GroupBox("Save Preset") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePreset)

                Button("Save Preset") {
                    savePreset()
                }
                .buttonStyle(.borderedProminent)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var presetsCard: some View {
        GroupBox("Saved Presets") {
            if viewModel.presets.isEmpty {
                Text("No presets saved yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.presets) { preset in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(.headline)
                                    Text("Updated \(preset.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Load") {
                                    viewModel.applyPreset(preset)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Delete", role: .destructive) {
                                    viewModel.deletePreset(preset)
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(presetSummary(for: preset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if preset.id != viewModel.presets.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func savePreset() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCurrentSettingsAsPreset(named: trimmed)
        presetName = ""
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func presetSummary(for preset: FanPreset) -> String {
        let settings = preset.settings
        let pid = settings.usePID ? "PID on" : "PID off"
        return "Sensor \(settings.sensorKey) • Fan \(settings.fanIndex) • \(settings.curve.count) points • \(Int(settings.minRPM))-\(Int(settings.maxRPM)) RPM • \(pid)"
    }
}

#Preview {
    ProfileView()
        .environment(FanControlViewModel())
        .frame(width: 760, height: 520)
}
