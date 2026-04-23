//
//  HIDSensorPoller.swift
//  SMCController
//
//  HID sensor polling for Apple Silicon
//

import Foundation

final class HIDSensorPoller {
    private var handle: UnsafeMutablePointer<HIDConnection>?
    private let interval: Double
    private var task: Task<Void, Never>?
    
    init(interval: Double) {
        self.interval = max(5.0, interval)
    }
    
    deinit {
        stop()
        if let h = handle {
            hid_close(h)
        }
    }
    
    func start(onUpdate: @MainActor @escaping ([String: Double]) -> Void,
               onError: @MainActor @escaping (String) -> Void = { _ in }) {
        stop()
        
        print("[HIDSensorPoller] Starting with interval: \(interval)s")
        
        // Open HID connection
        guard let h = hid_open() else {
            print("[HIDSensorPoller] ERROR: Failed to open HID connection")
            Task { @MainActor in
                onError("Failed to open HID sensors")
            }
            return
        }
        self.handle = h
        print("[HIDSensorPoller] HID connection opened successfully")
        
        task = Task.detached { [weak self] in
            guard let self else { 
                print("[HIDSensorPoller] ERROR: self is nil")
                return 
            }
            
            print("[HIDSensorPoller] Polling task started")
            var iteration = 0
            
            while !Task.isCancelled {
                iteration += 1
                print("[HIDSensorPoller] Iteration \(iteration) starting...")
                
                var sensors: [String: Double] = [:]
                
                // Enumerate temperature sensors (M4 has 40 sensors)
                var tempSensors: [HIDSensorInfo] = Array(repeating: HIDSensorInfo(
                    name: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
                    location: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
                    primaryUsagePage: 0,
                    primaryUsage: 0,
                    value: 0
                ), count: 64)
                
                let count = hid_enumerate_sensors(h, HIDSensorTypeTemperature, &tempSensors, 64)
                print("[HIDSensorPoller] Found \(count) temperature sensors")
                
                if count > 0 {
                    for i in 0..<Int(count) {
                        let namePtr = withUnsafeBytes(of: tempSensors[i].name) { 
                            $0.baseAddress!.assumingMemoryBound(to: CChar.self) 
                        }
                        if let name = String(cString: namePtr, encoding: .utf8) {
                            sensors[name] = tempSensors[i].value
                            if i < 5 { // Only log first 5 to avoid spam
                                print("[HIDSensorPoller]   \(name): \(tempSensors[i].value)°C")
                            }
                        }
                    }
                }
                
                let sensorsToSend = sensors
                print("[HIDSensorPoller] Calling MainActor.run with \(sensorsToSend.count) sensors...")
                await MainActor.run {
                    print("[HIDSensorPoller] MainActor callback executing")
                    if sensorsToSend.isEmpty {
                        onError("No HID temperature sensors found")
                    } else {
                        onUpdate(sensorsToSend)
                    }
                }
                
                print("[HIDSensorPoller] Sleeping for \(self.interval)s...")
                let ns = UInt64(self.interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
            
            print("[HIDSensorPoller] Polling task ended (cancelled)")
        }
    }
    
    func stop() {
        task?.cancel()
        task = nil
    }
}
