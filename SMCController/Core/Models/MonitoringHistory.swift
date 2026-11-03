//
//  MonitoringHistory.swift
//  SMCController
//
//  Rolling window of temperature and fan speed samples for charts.
//

import Foundation

struct MonitoringSample: Identifiable, Sendable, Equatable {
    let date: Date
    let temperatureC: Double?
    let fanRPM: Int?

    nonisolated var id: Date { date }
}

/// Keeps only the samples inside `window`, oldest first.
struct MonitoringHistory: Sendable {
    nonisolated static let defaultWindow: TimeInterval = 10 * 60
    nonisolated static let sampleInterval: TimeInterval = 2

    let window: TimeInterval
    private(set) var samples: [MonitoringSample] = []

    nonisolated init(window: TimeInterval = MonitoringHistory.defaultWindow) {
        self.window = max(1, window)
    }

    /// Appends a sample unless both values are missing, then drops expired samples.
    nonisolated mutating func record(temperatureC: Double?, fanRPM: Int?, at date: Date = Date()) {
        let temperature = temperatureC.flatMap { $0.isFinite ? $0 : nil }
        if temperature != nil || fanRPM != nil {
            samples.append(MonitoringSample(date: date, temperatureC: temperature, fanRPM: fanRPM))
        }
        let cutoff = date.addingTimeInterval(-window)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }) {
            if firstKept > 0 { samples.removeFirst(firstKept) }
        } else {
            samples.removeAll()
        }
    }

    nonisolated mutating func clear() {
        samples.removeAll()
    }
}
