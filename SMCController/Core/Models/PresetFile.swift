//
//  PresetFile.swift
//  SMCController
//
//  Shareable JSON format for fan presets.
//

import Foundation

/// File layout: `{ "formatVersion": 1, "presets": [ { "name": ..., "settings": { ... } } ] }`.
/// IDs and timestamps are not exported; they are assigned again on import.
enum PresetFile {
    nonisolated static let formatVersion = 1
    nonisolated static let fileExtension = "json"
    nonisolated static let defaultFilename = "SMCController Presets"

    struct Entry: Codable, Sendable {
        var name: String
        var settings: UserFanSettings
    }

    private struct Envelope: Codable {
        var formatVersion: Int
        var presets: [Entry]
    }

    enum FileError: LocalizedError {
        case unsupportedVersion(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return L10n.string("preset.file.unsupported.version", version)
            case .empty:
                return L10n.string("preset.file.empty")
            }
        }
    }

    static func encode(_ presets: [FanPreset]) throws -> Data {
        let envelope = Envelope(
            formatVersion: formatVersion,
            presets: presets.map { Entry(name: $0.name, settings: $0.settings) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    /// Accepts the envelope format, or a bare array of entries.
    static func decode(_ data: Data) throws -> [Entry] {
        let decoder = JSONDecoder()
        let entries: [Entry]
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            guard envelope.formatVersion <= formatVersion else {
                throw FileError.unsupportedVersion(envelope.formatVersion)
            }
            entries = envelope.presets
        } else {
            entries = try decoder.decode([Entry].self, from: data)
        }
        guard !entries.isEmpty else { throw FileError.empty }
        return entries
    }
}
