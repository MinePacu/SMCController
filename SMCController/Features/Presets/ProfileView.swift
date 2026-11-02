//
//  ProfileView.swift
//  SMCController
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(FanControlViewModel.self) private var viewModel
    @State private var presetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                messages
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

    @ViewBuilder
    private var messages: some View {
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
                .font(.callout)
        } else if let status = viewModel.statusMessage {
            Label(status, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
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
                    Text(viewModel.usePID ? L10n.string("Enabled") : L10n.string("Disabled"))
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
        GroupBox {
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
                                    Text(L10n.string("profile.updated.format", preset.updatedAt.formatted(date: .abbreviated, time: .shortened)))
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
        } label: {
            HStack {
                Text("Saved Presets")
                Spacer()
                Button {
                    importPresets()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                Button {
                    exportPresets()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.presets.isEmpty)
            }
        }
    }

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(PresetFile.defaultFilename).\(PresetFile.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.exportPresetsData().write(to: url, options: .atomic)
        } catch {
            viewModel.reportPresetFileError(error)
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.importPresets(from: Data(contentsOf: url))
        } catch {
            viewModel.reportPresetFileError(error)
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
        let pid = settings.usePID ? L10n.string("profile.pid.on") : L10n.string("profile.pid.off")
        return L10n.string(
            "profile.preset.summary.format",
            settings.sensorKey,
            settings.fanIndex,
            settings.curve.count,
            Int(settings.minRPM),
            Int(settings.maxRPM),
            pid
        )
    }
}

#Preview {
    ProfileView()
        .environment(FanControlViewModel())
        .frame(width: 760, height: 520)
}
