//
//  SensorLayer.swift
//  SMCController
//
//  Read-only sensor polling layer on top of SMCService.
//

import Foundation

enum SensorUnit: String, Sendable {
    case celsius = "°C"
    case rpm = "RPM"
    case raw = "raw"
    case watt = "W"
}

struct SensorDefinition: Sendable {
    enum Kind: Sendable {
        case temperature
        case rpm(fanIndex: Int)
        case power
    }

    var name: String
    var keys: [String]          // primary + fallback keys (for newer SoCs)
    var unit: SensorUnit
    var kind: Kind
    var transform: @Sendable (Double) -> Double
}

struct SensorReading: Sendable {
    var name: String
    var value: Double
    var unit: SensorUnit
}

/// Polls sensors periodically and reports back to the caller on the main actor.
final class SensorPoller {
    private let smc: SMCService
    private let interval: Double
    private let definitions: [SensorDefinition]
    private let extraKeys: [String]
    private var task: Task<Void, Never>?

    init(smc: SMCService,
         interval: Double,
         definitions: [SensorDefinition],
         extraKeys: [String] = []) {
        self.smc = smc
        self.interval = max(5.0, interval)
        self.definitions = definitions
        self.extraKeys = extraKeys
    }

    func start(onUpdate: @MainActor @escaping ([SensorReading]) -> Void,
               onError: @MainActor @escaping (String) -> Void = { _ in }) {
        stop()
        task = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                var readings: [SensorReading] = []
                var lastError: String?

                for def in self.definitions {
                    let (reading, err) = await MainActor.run { self.read(def) }
                    if let reading {
                        readings.append(reading)
                    } else if let err {
                        lastError = err
                    }
                }

                // Unknown sensor keys (user-provided) to absorb new SoC changes.
                for key in self.extraKeys {
                    let value = await MainActor.run { try? self.smc.readTemperatureC(key: key) }
                    if let v = value, !v.isNaN {
                        readings.append(SensorReading(name: "Unknown \(key)", value: v, unit: .celsius))
                    }
                }

                let readingsToSend = readings
                let errorToSend = lastError
                await MainActor.run {
                    if readingsToSend.isEmpty, let err = errorToSend {
                        onError(err)
                    }
                    onUpdate(readingsToSend)
                }

                let ns = UInt64(self.interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func read(_ def: SensorDefinition) -> (SensorReading?, String?) {
        switch def.kind {
        case .temperature:
            for key in def.keys {
                do {
                    let v = try smc.readTemperatureC(key: key)
                    if !v.isNaN {
                        return (SensorReading(name: def.name, value: def.transform(v), unit: def.unit), nil)
                    }
                } catch {
                    // Try next key silently
                    continue
                }
            }
            // Only report error if ALL keys failed
            return (nil, "Read \(def.name) failed: all keys unavailable")
        case .rpm(let idx):
            do {
                let v = try smc.currentRPM(fan: idx)
                return (SensorReading(name: def.name, value: def.transform(Double(v)), unit: def.unit), nil)
            } catch {
                // Fan may not exist or be accessible; return nil without error on first failure
                return (nil, nil)
            }
        case .power:
            for key in def.keys {
                do {
                    let v = try smc.readPowerWatts(key: key)
                    if !v.isNaN {
                        return (SensorReading(name: def.name, value: def.transform(v), unit: def.unit), nil)
                    }
                } catch {
                    continue
                }
            }
            return (nil, "Read \(def.name) failed: all keys unavailable")
        }
    }
}
