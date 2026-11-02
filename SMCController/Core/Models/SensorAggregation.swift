//
//  SensorAggregation.swift
//  SMCController
//
//  How several temperature sensors are combined into the value that drives the curve,
//  and which fans the curve is applied to.
//

import Foundation

nonisolated public enum SensorAggregation: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Only the primary sensor drives the curve.
    case primary
    /// The hottest of the selected sensors drives the curve.
    case maximum
    /// The mean of the selected sensors drives the curve.
    case average

    public var id: String { rawValue }

    var localizedTitleKey: String {
        switch self {
        case .primary: "sensor.aggregation.primary"
        case .maximum: "sensor.aggregation.maximum"
        case .average: "sensor.aggregation.average"
        }
    }

    /// Returns nil for an empty input.
    nonisolated func combine(_ values: [Double]) -> Double? {
        guard let first = values.first else { return nil }
        switch self {
        case .primary:
            return first
        case .maximum:
            return values.max()
        case .average:
            return values.reduce(0, +) / Double(values.count)
        }
    }
}

enum FanSelection {
    /// SMC exposes fans F0...F9.
    nonisolated static let maximumFanCount = 10

    /// Sorted, unique, in-range fan indices; falls back to fan 0 when nothing valid remains.
    nonisolated static func normalized(_ indices: [Int]) -> [Int] {
        let valid = Set(indices.filter { (0..<maximumFanCount).contains($0) })
        return valid.isEmpty ? [0] : valid.sorted()
    }

    /// Bit mask for the helper's `setMode` request (bit 0 = fan 0).
    nonisolated static func mask(for indices: [Int]) -> Int {
        normalized(indices).reduce(0) { $0 | (1 << $1) }
    }

    /// The fans to drive: every detected fan, or the single selected one.
    /// With an unknown fan count, "all fans" falls back to fan 0 and a single fan is
    /// kept as chosen (the helper still rejects fans that do not exist).
    nonisolated static func indices(controlAllFans: Bool, fanIndex: Int, fanCount: Int?) -> [Int] {
        guard let fanCount, fanCount > 0 else {
            return normalized([controlAllFans ? 0 : fanIndex])
        }
        let count = min(fanCount, maximumFanCount)
        if controlAllFans {
            return Array(0..<count)
        }
        return [min(max(0, fanIndex), count - 1)]
    }
}

enum SensorKeyList {
    /// Splits a comma-separated list, trims whitespace, and drops empties and duplicates.
    nonisolated static func parse(_ text: String) -> [String] {
        unique(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    nonisolated static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
