//
//  SMCAppleSilicon.swift
//  SMCController
//
//  Apple Silicon HID sensor support
//

import Foundation

final class SMCAppleSilicon {
    private var handle: UnsafeMutablePointer<HIDConnection>?
    
    init() throws {
        print("[Swift HID] Initializing Apple Silicon HID sensors...")
        guard let h = hid_open() else {
            print("[Swift HID] ERROR: hid_open() returned NULL")
            throw SMCError.openFailed
        }
        self.handle = h
        print("[Swift HID] Apple Silicon HID initialized successfully")
    }
    
    deinit {
        if let h = handle {
            print("[Swift HID] Closing HID connection...")
            hid_close(h)
        }
    }
    
    private func requireHandle() throws -> UnsafeMutablePointer<HIDConnection> {
        guard let h = handle else {
            print("[Swift HID] ERROR: handle is NULL")
            throw SMCError.openFailed
        }
        return h
    }
    
    func fanCount() throws -> Int {
        // Apple Silicon Macs typically have 1-2 fans, but HID doesn't expose fan count
        // We'll enumerate and count actual fan sensors
        print("[Swift HID] Getting fan count...")
        // For now, assume 0 fans (HID doesn't provide fan info on most M-series Macs)
        return 0
    }
    
    func currentRPM(fan index: Int) throws -> Int {
        print("[Swift HID] Fan RPM not available via HID on Apple Silicon")
        throw SMCError.unsupported
    }
    
    func minRPM(fan index: Int) throws -> Int {
        throw SMCError.unsupported
    }
    
    func maxRPM(fan index: Int) throws -> Int {
        throw SMCError.unsupported
    }
    
    func setTargetRPM(fan index: Int, rpm: Int) throws {
        print("[Swift HID] Fan control not available via HID on Apple Silicon")
        throw SMCError.unsupported
    }
    
    func setManualMode(_ enabled: Bool) throws {
        throw SMCError.unsupported
    }
    
    func readTemperatureC(key: String) throws -> Double {
        print("[Swift HID] Reading temperature for key: \(key)")
        let h = try requireHandle()
        
        // Try to read with sensor name matching
        let temp = hid_read_temperature(h, key)
        if temp.isNaN {
            print("[Swift HID] Could not read temperature for \(key)")
            throw SMCError.readFailed(key)
        }
        
        print("[Swift HID] Temperature for \(key): \(temp)°C")
        return temp
    }
    
    // Get all available temperature sensors
    func enumerateTemperatureSensors() -> [(name: String, value: Double)] {
        guard let h = handle else { return [] }
        
        var sensors: [HIDSensorInfo] = Array(repeating: HIDSensorInfo(
            name: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            location: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            primaryUsagePage: 0,
            primaryUsage: 0,
            value: 0.0
        ), count: 32)
        
        let count = hid_enumerate_sensors(h, HIDSensorTypeTemperature, &sensors, Int32(sensors.count))
        
        guard count > 0 else { return [] }
        
        var result: [(String, Double)] = []
        for i in 0..<Int(count) {
            let namePtr = withUnsafeBytes(of: sensors[i].name) { $0.baseAddress!.assumingMemoryBound(to: CChar.self) }
            if let name = String(cString: namePtr, encoding: .utf8) {
                result.append((name, sensors[i].value))
            }
        }
        
        return result
    }
}
