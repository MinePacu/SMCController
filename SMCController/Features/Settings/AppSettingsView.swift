//
//  AppSettingsView.swift
//  SMCController
//

import SwiftUI

struct AppSettingsView: View {
    @Bindable var languageSettings: AppLanguageSettings

    var body: some View {
        Form {
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
        .frame(width: 420)
    }
}

#Preview {
    AppSettingsView(languageSettings: AppLanguageSettings())
}
