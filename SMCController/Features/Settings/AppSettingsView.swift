//
//  AppSettingsView.swift
//  SMCController
//

import SwiftUI

struct AppSettingsView: View {
    @Bindable var languageSettings: AppLanguageSettings
    @Bindable var preferences: AppPreferences

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { preferences.launchAtLogin },
            set: { preferences.setLaunchAtLogin($0) }
        )
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("settings.launchAtLogin", isOn: launchAtLoginBinding)
                if preferences.launchAtLoginNeedsApproval {
                    HStack {
                        Text("settings.launchAtLogin.approval")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("settings.launchAtLogin.openSettings") {
                            preferences.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }
                if let error = preferences.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("settings.monitorOnLaunch", isOn: $preferences.monitorOnLaunch)
                Toggle("settings.resumeControlOnLaunch", isOn: $preferences.resumeControlOnLaunch)
                Text("settings.resumeControlOnLaunch.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("settings.showMenuBarExtra", isOn: $preferences.showMenuBarExtra)
                Toggle("settings.notifyOnControlStop", isOn: $preferences.notifyOnControlStop)
            }

            Section("Language") {
                Picker("App Language", selection: $languageSettings.selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.localizedTitleKey))
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)

                Text("settings.language.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // The user may have changed the login item in System Settings meanwhile.
            preferences.refreshLaunchAtLogin()
        }
    }
}

#Preview {
    AppSettingsView(languageSettings: AppLanguageSettings(), preferences: AppPreferences())
}
