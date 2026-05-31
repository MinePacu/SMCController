//
//  L10n.swift
//  SMCController
//

import Foundation

enum L10n {
    private static var language: AppLanguage = .system

    static func configure(language: AppLanguage) {
        self.language = language
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: language.localizationBundle, comment: "")
        return String(format: format, locale: language.locale, arguments: arguments)
    }
}
