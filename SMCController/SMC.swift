//
//  SMC.swift
//  SMCController
//
//  Swift wrapper around low-level SMCBridge
//

import Foundation
import Combine

enum SMCError: Error {
    case openFailed
    case readFailed(String)
    case writeFailed(String)
    case unsupported
}

final class SMCService {
    private var handle: UnsafeMutablePointer<SMCConnection>?
    
    // Internal access for direct SMC operations
    var connection: UnsafeMutablePointer<SMCConnection>? {
        return handle
    }

    init() throws {
        print("[Swift SMC] Initializing SMCService...")
        guard let h = smc_open() else {
            print("[Swift SMC] ERROR: smc_open() returned NULL")
            throw SMCError.openFailed
        }
        self.handle = h
        print("[Swift SMC] SMCService initialized successfully, handle: \(h)")
    }

    deinit {
        if let h = handle {
            print("[Swift SMC] Closing SMC connection...")
            smc_close(h)
        }
    }

    private func requireHandle() throws -> UnsafeMutablePointer<SMCConnection> {
        guard let h = handle else {
            print("[Swift SMC] ERROR: handle is NULL in requireHandle()")
            throw SMCError.openFailed
        }
        return h
    }

    func fanCount() throws -> Int {
        print("[Swift SMC] Getting fan count...")
        let h = try requireHandle()
        let c = smc_read_fan_count(h)
        if c < 0 {
            print("[Swift SMC] ERROR: smc_read_fan_count returned \(c)")
            throw SMCError.readFailed("FNum")
        }
        print("[Swift SMC] Fan count: \(c)")
        return Int(c)
    }

    func currentRPM(fan index: Int) throws -> Int {
        let h = try requireHandle()
        
        // Use direct smc_read_key like SMCSensorDebugView does
        let key = String(format: "F%dAc", index)
        
        // First, read key info to get proper data size
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        
        let infoResult = smc_read_key_info(h, key, &dataSize, &dataType)
        if infoResult != 0 {
            throw SMCError.readFailed(key)
        }
        
        // Now read actual value
        var buffer = [UInt8](repeating: 0, count: 32)
        var actualDataSize: UInt32 = 0
        var actualDataType: UInt32 = 0
        
        let result = smc_read_key(h, key, &buffer, dataSize, &actualDataSize, &actualDataType)
        if result <= 0 {
            throw SMCError.readFailed(key)
        }
        
        // Decode like SMCSensorDebugView
        let rpm = decodeRPM(buffer: buffer, dataSize: Int(dataSize), dataType: dataType)
        return rpm
    }
    
    private func decodeRPM(buffer: [UInt8], dataSize: Int, dataType: UInt32) -> Int {
        // Convert type code to string
        let typeBytes = [
            UInt8((dataType >> 24) & 0xFF),
            UInt8((dataType >> 16) & 0xFF),
            UInt8((dataType >> 8) & 0xFF),
            UInt8(dataType & 0xFF)
        ]
        let typeStr = String(bytes: typeBytes, encoding: .ascii) ?? "????"
        
        guard dataSize >= 2 else { return 0 }
        
        switch typeStr {
        case "fpe2":
            // Fixed point e2: divide by 4
            let value = (UInt16(buffer[0]) << 8) | UInt16(buffer[1])
            let rpm = Int(Double(Int16(bitPattern: value)) / 4.0)
            return rpm
        case "ui16":
            // Unsigned 16-bit
            let value = (UInt16(buffer[0]) << 8) | UInt16(buffer[1])
            return Int(value)
        case "flt ":
            // Float (little-endian) - same as SMCSensorDebugView
            if dataSize >= 4 {
                let value = UInt32(buffer[0]) | (UInt32(buffer[1]) << 8) |
                           (UInt32(buffer[2]) << 16) | (UInt32(buffer[3]) << 24)
                let floatValue = Float(bitPattern: value)
                let rpm = Int(floatValue)
                return rpm
            } else {
                let value = (UInt16(buffer[0]) << 8) | UInt16(buffer[1])
                return Int(value)
            }
        default:
            // Default to ui16
            let value = (UInt16(buffer[0]) << 8) | UInt16(buffer[1])
            return Int(value)
        }
    }

    func minRPM(fan index: Int) throws -> Int {
        let h = try requireHandle()
        
        let key = String(format: "F%dMn", index)
        
        // First, read key info to get proper data size
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        
        let infoResult = smc_read_key_info(h, key, &dataSize, &dataType)
        if infoResult != 0 {
            throw SMCError.readFailed(key)
        }
        
        // Now read actual value
        var buffer = [UInt8](repeating: 0, count: 32)
        var actualDataSize: UInt32 = 0
        var actualDataType: UInt32 = 0
        
        let result = smc_read_key(h, key, &buffer, dataSize, &actualDataSize, &actualDataType)
        if result <= 0 {
            throw SMCError.readFailed(key)
        }
        
        let rpm = decodeRPM(buffer: buffer, dataSize: Int(dataSize), dataType: dataType)
        return rpm
    }

    func maxRPM(fan index: Int) throws -> Int {
        let h = try requireHandle()
        
        let key = String(format: "F%dMx", index)
        
        // First, read key info to get proper data size
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        
        let infoResult = smc_read_key_info(h, key, &dataSize, &dataType)
        if infoResult != 0 {
            throw SMCError.readFailed(key)
        }
        
        // Now read actual value
        var buffer = [UInt8](repeating: 0, count: 32)
        var actualDataSize: UInt32 = 0
        var actualDataType: UInt32 = 0
        
        let result = smc_read_key(h, key, &buffer, dataSize, &actualDataSize, &actualDataType)
        if result <= 0 {
            throw SMCError.readFailed(key)
        }
        
        let rpm = decodeRPM(buffer: buffer, dataSize: Int(dataSize), dataType: dataType)
        return rpm
    }
    
    func targetRPM(fan index: Int) throws -> Int {
        let h = try requireHandle()
        let key = "F\(index)Tg"
        
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        
        let infoResult = smc_read_key_info(h, key, &dataSize, &dataType)
        if infoResult != 0 {
            throw SMCError.readFailed(key)
        }
        
        var buffer = [UInt8](repeating: 0, count: 32)
        var actualDataSize: UInt32 = 0
        var actualDataType: UInt32 = 0
        
        let result = smc_read_key(h, key, &buffer, dataSize, &actualDataSize, &actualDataType)
        if result <= 0 {
            throw SMCError.readFailed(key)
        }
        
        let rpm = decodeRPM(buffer: buffer, dataSize: Int(dataSize), dataType: dataType)
        return rpm
    }

    nonisolated func setTargetRPM(fan index: Int, rpm: Int) async throws {
        print("[Swift SMC] Setting fan \(index) target RPM to \(rpm)...")
        
        // Try daemon only (Helper Tool disabled - causes conflicts)
        do {
            try DaemonClient.shared.setFanSpeed(fan: index, rpm: rpm)
            print("[Swift SMC] ✅ Set fan \(index) target RPM to \(rpm) via daemon")
            return
        } catch {
            print("[Swift SMC] ❌ Daemon error: \(error)")
            // Re-throw the error without falling back to Helper Tool
            throw error
        }
    }

    nonisolated func setManualMode(_ enabled: Bool) async throws {
        print("[Swift SMC] Setting manual mode: \(enabled)...")
        
        // Try daemon only (Helper Tool disabled - causes conflicts)
        do {
            try DaemonClient.shared.setManualMode(enabled: enabled)
            print("[Swift SMC] ✅ Set manual mode to \(enabled) via daemon")
            return
        } catch {
            print("[Swift SMC] ❌ Daemon error: \(error)")
            // Re-throw the error without falling back to Helper Tool
            throw error
        }
    }

    func readTemperatureC(key: String) throws -> Double {
        let h = try requireHandle()
        
        // First, read key info to get proper data size (like SMCSensorDebugView)
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        
        let infoResult = smc_read_key_info(h, key, &dataSize, &dataType)
        if infoResult != 0 {
            throw SMCError.readFailed(key)
        }
        
        // Now read actual value
        var buffer = [UInt8](repeating: 0, count: 32)
        var actualDataSize: UInt32 = 0
        var actualDataType: UInt32 = 0
        
        let result = smc_read_key(h, key, &buffer, dataSize, &actualDataSize, &actualDataType)
        if result <= 0 {
            throw SMCError.readFailed(key)
        }
        
        // Decode like SMCSensorDebugView
        let temp = decodeTemperature(buffer: buffer, dataSize: Int(dataSize), dataType: dataType)
        if temp.isNaN || temp <= 0 || temp > 150 {
            throw SMCError.readFailed(key)
        }
        
        return temp
    }
    
    private func decodeTemperature(buffer: [UInt8], dataSize: Int, dataType: UInt32) -> Double {
        // Convert type code to string
        let typeBytes = [
            UInt8((dataType >> 24) & 0xFF),
            UInt8((dataType >> 16) & 0xFF),
            UInt8((dataType >> 8) & 0xFF),
            UInt8(dataType & 0xFF)
        ]
        let typeStr = String(bytes: typeBytes, encoding: .ascii) ?? "????"
        
        guard dataSize >= 2 else { return Double.nan }
        
        switch typeStr {
        case "fpe2":
            // Fixed point e2: divide by 4
            let value = (UInt16(buffer[0]) << 8) | UInt16(buffer[1])
            return Double(Int16(bitPattern: value)) / 4.0
        case "sp78", "sp87":
            // Signed fixed point: divide by 256
            let value = (UInt16(buffer[0]) << 8) | UInt16(buffer[1])
            return Double(Int16(bitPattern: value)) / 256.0
        case "ui16":
            // Unsigned 16-bit (rare for temperature but handle it)
            let value = (UInt16(buffer[0]) << 8) | UInt16(buffer[1])
            return Double(value)
        case "flt ":
            // Float (little-endian)
            if dataSize >= 4 {
                let value = UInt32(buffer[0]) | (UInt32(buffer[1]) << 8) |
                           (UInt32(buffer[2]) << 16) | (UInt32(buffer[3]) << 24)
                return Double(Float(bitPattern: value))
            }
        default:
            break
        }
        
        return Double.nan
    }
}
