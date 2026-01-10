//
//  PrivilegeStatusView.swift
//  SMCController
//
//  Shows privilege status and instructions
//

import SwiftUI

struct PrivilegeStatusView: View {
    @StateObject private var privilegeHelper = PrivilegeHelper.shared
    @State private var helperInstalled = SMCHelperProxy.shared.isInstalled
    @State private var isInstalling = false
    @State private var installError: String?
    
    var body: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: helperInstalled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.title2)
                            .foregroundColor(helperInstalled ? .green : .orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privileged Helper Tool")
                                .font(.headline)
                            
                            if helperInstalled {
                                Text("Installed - Fan control enabled")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Not installed - Fan control disabled")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: checkStatus) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh status")
                    }
                }
                .padding(8)
            } label: {
                Text("Helper Status")
            }
            
            if !helperInstalled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            Text("Install Helper Tool")
                                .font(.headline)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The helper tool runs in the background with root privileges, allowing fan control without running the entire app as root.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Installation steps:")
                                .font(.subheadline)
                                .padding(.top, 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Build helper binary", systemImage: "1.circle.fill")
                                    .font(.caption)
                                Label("Enter admin password", systemImage: "2.circle.fill")
                                    .font(.caption)
                                Label("Install to system location", systemImage: "3.circle.fill")
                                    .font(.caption)
                            }
                            .padding(.leading, 8)
                            
                            Button(action: installHelper) {
                                HStack {
                                    if isInstalling {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "lock.shield.fill")
                                        Text("Install Helper Tool")
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isInstalling)
                            .padding(.top, 4)
                            
                            if let error = installError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Text("Setup Required")
                }
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ready to Control Fans")
                                    .font(.headline)
                                
                                Text("Helper tool is installed and working")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Label("No sudo password required", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Label("All macOS UI features work normally", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Label("Secure privilege separation", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(8)
                } label: {
                    Text("Status")
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func checkStatus() {
        SMCHelperProxy.shared.checkInstallation()
        helperInstalled = SMCHelperProxy.shared.isInstalled
    }
    
    private func installHelper() {
        isInstalling = true
        installError = nil
        
        Task {
            do {
                try SMCHelperProxy.shared.installHelper()
                await MainActor.run {
                    helperInstalled = true
                    isInstalling = false
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }
}

#Preview {
    PrivilegeStatusView()
}
