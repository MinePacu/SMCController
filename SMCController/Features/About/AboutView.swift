//
//  AboutView.swift
//  SMCController
//

import SwiftUI

struct AboutView: View {
    private var versionText: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return nil
        }
        return "Version \(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("SMC Controller", systemImage: "fanblades.fill")
                        .font(.largeTitle.weight(.semibold))

                    if let versionText {
                        Text(versionText)
                            .foregroundStyle(.secondary)
                    }

                    Text("Monitor temperatures, tune fan curves, and save reusable cooling presets for macOS hardware that exposes SMC fan control.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox("What This App Does") {
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Controls fan RPM using a temperature curve with optional PID tuning.")
                        bullet("Monitors CPU, GPU, fan, and power metrics where hardware access is available.")
                        bullet("Saves the current configuration automatically and supports named presets.")
                    }
                }

                GroupBox("Use With Care") {
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Manual fan control can override the system's thermal policy.")
                        bullet("Apple Silicon fan control remains hardware-dependent and may be limited.")
                        bullet("If fan behavior looks wrong, stop control and return to automatic mode.")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .padding(.top, 7)
            Text(text)
        }
    }
}

#Preview {
    AboutView()
        .frame(width: 640, height: 420)
}
