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

                if privilegeHelper.availability != .ready {
                    setupCard
                } else {
                    readyCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
            .task {
                await privilegeHelper.refreshStatus()
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
                        Text(statusTitle)
                            .font(.headline)
                        Text(privilegeHelper.statusMessage ?? "Checking helper status...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await privilegeHelper.refreshStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh status")
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    if HelperBuildMode.usesLocalUnsignedHelper {
                        statusRow("Local helper bundled", isOn: privilegeHelper.helperInstalled)
                        statusRow("Session active", isOn: privilegeHelper.daemonRunning)
                        statusRow("Private helper channel connected", isOn: privilegeHelper.availability == .ready)
                    } else {
                        statusRow("Helper installed", isOn: privilegeHelper.helperInstalled)
                        statusRow("Daemon running", isOn: privilegeHelper.daemonRunning)
                        statusRow("Secure XPC connection", isOn: privilegeHelper.availability == .ready)
                    }
                    statusRow("Fan control available", isOn: privilegeHelper.hasPrivileges)
                }
            }
            .padding(8)
        }
    }

    private var setupCard: some View {
        GroupBox("Setup Required") {
            VStack(alignment: .leading, spacing: 12) {
                Text(setupDescription)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(setupStepsTitle)
                        .font(.subheadline.weight(.medium))
                    Text("1. macOS will ask for your administrator password.")
                    if HelperBuildMode.usesLocalUnsignedHelper {
                        Text("2. The bundled helper will run only for this app session.")
                        Text("3. The session ends when the app quits.")
                    } else {
                        Text("2. The signed helper will be installed or updated.")
                        Text("3. Future fan control changes should work without repeated prompts.")
                    }
                }
                .font(.caption)

                Button(action: enableFanControl) {
                    HStack {
                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "lock.shield")
                            Text(setupButtonTitle)
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
                if HelperBuildMode.usesLocalUnsignedHelper {
                    Label("Session active", systemImage: "checkmark.circle")
                    Label("Private helper channel connected", systemImage: "checkmark.circle")
                    Label("The session ends when the app quits", systemImage: "clock")
                } else {
                    Label("Manual fan control is available", systemImage: "checkmark.circle")
                    Label("The helper daemon is already running", systemImage: "checkmark.circle")
                    Label("Monitoring can continue without additional prompts", systemImage: "checkmark.circle")
                }
            }
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }

    private var statusTitle: String {
        if HelperBuildMode.usesLocalUnsignedHelper {
            return privilegeHelper.availability == .ready ? "Session active" : "Local Fan Helper Required"
        }
        switch privilegeHelper.availability {
        case .ready:
            return L10n.string("Fan Control Ready")
        case .updateRequired:
            return "Helper Update Required"
        case .notInstalled, .failed:
            return L10n.string("Helper Required")
        }
    }

    private var setupDescription: String {
        if HelperBuildMode.usesLocalUnsignedHelper {
            switch privilegeHelper.availability {
            case .failed(let message):
                return "The local helper session could not be verified: \(message)"
            case .updateRequired:
                return "This app and its bundled local helper do not use the same protocol version."
            case .notInstalled, .ready:
                return "Start a private privileged helper session for fan writes. Nothing is installed in /Library."
            }
        }
        switch privilegeHelper.availability {
        case .updateRequired:
            return "An older helper is installed. Update it to use the secure XPC connection required for fan control."
        case .failed(let message):
            return "The helper could not be verified: \(message)"
        case .notInstalled, .ready:
            return "Temperature monitoring can work without extra privileges, but fan write control requires the helper daemon."
        }
    }

    private var setupStepsTitle: String {
        if HelperBuildMode.usesLocalUnsignedHelper {
            return "When you start the local helper:"
        }
        return privilegeHelper.availability == .updateRequired
            ? "When you update the helper:"
            : "When you enable fan control:"
    }

    private var setupButtonTitle: String {
        if HelperBuildMode.usesLocalUnsignedHelper {
            return "Start Local Fan Helper"
        }
        return privilegeHelper.availability == .updateRequired
            ? "Update Fan Control Helper"
            : "Enable Fan Control"
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
            let success = await privilegeHelper.requestPrivilegesAndRelaunch()
            isInstalling = false

            if !success {
                installError = L10n.string("privileges.install.error")
            }
        }
    }
}

#Preview {
    PrivilegeStatusView()
}
