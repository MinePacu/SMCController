//
//  MonitoringHistoryChart.swift
//  SMCController
//
//  Temperature and fan speed over the last few minutes.
//

import SwiftUI
import Charts

struct MonitoringHistoryChart: View {
    let samples: [MonitoringSample]
    var criticalTempC: Double?

    private var temperatureSamples: [MonitoringSample] {
        samples.filter { $0.temperatureC != nil }
    }

    private var rpmSamples: [MonitoringSample] {
        samples.filter { $0.fanRPM != nil }
    }

    /// The critical line is only drawn once temperatures get near it, so a cool
    /// machine still gets a readable scale.
    private var visibleCriticalTempC: Double? {
        guard let criticalTempC,
              let maxTemp = temperatureSamples.compactMap(\.temperatureC).max(),
              maxTemp >= criticalTempC - 15 else { return nil }
        return criticalTempC
    }

    var body: some View {
        if samples.count < 2 {
            Text("history.empty")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                temperatureChart
                rpmChart
            }
        }
    }

    private var temperatureChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Temperature (°C)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(temperatureSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("°C", sample.temperatureC ?? 0)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                }
                if let criticalTempC = visibleCriticalTempC {
                    RuleMark(y: .value("Critical", criticalTempC))
                        .foregroundStyle(.red.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(L10n.string("history.critical.format", Int(criticalTempC)))
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                }
            }
            .chartYScale(domain: temperatureDomain)
            .chartXAxis { timeAxis }
            .frame(height: 120)
        }
    }

    private var rpmChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fan RPM")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(rpmSamples) { sample in
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("RPM", sample.fanRPM ?? 0)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.stepEnd)
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis { timeAxis }
            .frame(height: 100)
        }
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: .stride(by: .minute, count: 2)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.hour().minute())
        }
    }

    /// Keeps the critical line visible and gives the curve some headroom.
    private var temperatureDomain: ClosedRange<Double> {
        let values = temperatureSamples.compactMap(\.temperatureC)
        var low = (values.min() ?? 30) - 5
        var high = (values.max() ?? 80) + 5
        if let criticalTempC = visibleCriticalTempC { high = max(high, criticalTempC + 3) }
        low = max(0, low)
        if high - low < 10 { high = low + 10 }
        return low...high
    }
}
