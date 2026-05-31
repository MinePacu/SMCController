//
//  AppLanguage.swift
//  SMCController
//

import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"
    case japanese = "ja"

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .korean:
            "ko"
        case .japanese:
            "ja"
        }
    }

    var locale: Locale {
        if let localeIdentifier {
            Locale(identifier: localeIdentifier)
        } else {
            .autoupdatingCurrent
        }
    }

    var localizedTitleKey: String {
        switch self {
        case .system:
            "System Default"
        case .english:
            "English"
        case .korean:
            "Korean"
        case .japanese:
            "Japanese"
        }
    }

    var localizationBundle: Bundle {
        guard let localeIdentifier,
              let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }

        return bundle
    }
}

@Observable
final class AppLanguageSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "com.minepacu.smccontroller.appLanguage"

    var selectedLanguage: AppLanguage {
        didSet {
            defaults.set(selectedLanguage.rawValue, forKey: storageKey)
            L10n.configure(language: selectedLanguage)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedLanguage = defaults.string(forKey: storageKey)
            .flatMap(AppLanguage.init(rawValue:))

        selectedLanguage = storedLanguage ?? .system
        L10n.configure(language: selectedLanguage)
    }
}
