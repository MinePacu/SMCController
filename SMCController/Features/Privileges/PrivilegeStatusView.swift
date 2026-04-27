//
//  PrivilegeStatusView.swift
//  SMCController
//

import SwiftUI

struct PrivilegeStatusView: View {
    @State private var privilegeHelper = PrivilegeHelper.shared
    @State private var isInstalling = false
    @State private var installError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                helperStatusCard

                if !privilegeHelper.hasPrivileges {
                    setupCard
                } else {
                    readyCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
            .task {
                privilegeHelper.refreshStatus()
            }
        }
    }

    private var helperStatusCard: some View {
        GroupBox("Helper Status") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: privilegeHelper.hasPrivileges ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(privilegeHelper.hasPrivileges ? .green : .orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(privilegeHelper.hasPrivileges ? "Fan Control Ready" : "Helper Required")
                            .font(.headline)
                        Text(privilegeHelper.statusMessage ?? "Checking helper status...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        privilegeHelper.refreshStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh status")
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    statusRow("Helper installed", isOn: privilegeHelper.helperInstalled)
                    statusRow("Daemon running", isOn: privilegeHelper.daemonRunning)
                    statusRow("Fan control available", isOn: privilegeHelper.hasPrivileges)
                }
            }
            .padding(8)
        }
    }

    private var setupCard: some View {
        GroupBox("Setup Required") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Temperature monitoring can work without extra privileges, but fan write control requires the helper daemon.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("When you enable fan control:")
                        .font(.subheadline.weight(.medium))
                    Text("1. macOS will ask for your administrator password.")
                    Text("2. The helper will be installed or started if needed.")
                    Text("3. Future fan control changes should work without repeated prompts.")
                }
                .font(.caption)

                Button(action: enableFanControl) {
                    HStack {
                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "lock.shield")
                            Text("Enable Fan Control")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isInstalling)

                if let installError {
                    Text(installError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)
        }
    }

    private var readyCard: some View {
        GroupBox("Ready") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Manual fan control is available", systemImage: "checkmark.circle")
                Label("The helper daemon is already running", systemImage: "checkmark.circle")
                Label("Monitoring can continue without additional prompts", systemImage: "checkmark.circle")
            }
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }

    private func statusRow(_ title: String, isOn: Bool) -> some View {
        HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isOn ? .green : .secondary)
            Text(title)
            Spacer()
        }
        .font(.caption)
    }

    private func enableFanControl() {
        isInstalling = true
        installError = nil

        Task { @MainActor in
            let success = privilegeHelper.requestPrivilegesAndRelaunch()
            isInstalling = false

            if !success {
                installError = "Could not install or start the helper daemon. Check that the bundled helper resources are present and try again."
            }
        }
    }
}

#Preview {
    PrivilegeStatusView()
}
