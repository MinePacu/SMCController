//
//  MenuBarContent.swift
//  SMCController
//
//  Menu bar item: live temperature / fan speed and quick controls.
//

import SwiftUI
import AppKit

let mainWindowID = "main-window"

struct MenuBarLabel: View {
    var viewModel: FanControlViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.isRunning ? "fan.fill" : "fan")
            if let text = summaryText {
                Text(text)
                    .monospacedDigit()
            }
        }
    }

    private var summaryText: String? {
        guard viewModel.isMonitoring else { return nil }
        var parts: [String] = []
        if let temp = viewModel.lastTempC, temp.isFinite {
            parts.append("\(Int(temp.rounded()))°")
        }
        if let rpm = viewModel.fanRPM {
            parts.append("\(rpm)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

struct MenuBarContent: View {
    var viewModel: FanControlViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            Text(L10n.string("menu.temperature.format", formattedTemp(viewModel.lastTempC)))
            Text(L10n.string("menu.fan.format", formattedRPM(viewModel.fanRPM)))
            Text(viewModel.isRunning ? L10n.string("menu.state.running") : L10n.string("menu.state.stopped"))

            if let error = viewModel.errorMessage {
                Text(error)
            }

            Divider()

            Button(viewModel.isRunning ? L10n.string("Stop") : L10n.string("Start")) {
                if viewModel.isRunning { viewModel.stop() } else { viewModel.start() }
            }
            if !viewModel.isMonitoring {
                Button("Monitor Only") { viewModel.startMonitoringOnly() }
            }

            if viewModel.hasSavedPresets {
                Menu("Presets") {
                    ForEach(viewModel.presets) { preset in
                        Button(preset.name) { viewModel.applyPreset(preset) }
                    }
                }
            }

            Divider()

            Button("menu.open.window") { showMainWindow() }
            Button("menu.settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("menu.quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    /// Brings the existing main window forward, or opens one if it was closed.
    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let existing = NSApp.windows.first { window in
            window.identifier?.rawValue.hasPrefix(mainWindowID) == true
        }
        if let existing {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: mainWindowID)
        }
    }

    private func formattedTemp(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded())) °C"
    }

    private func formattedRPM(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value) RPM"
    }
}
