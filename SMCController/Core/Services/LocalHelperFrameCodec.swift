//
//  LocalHelperFrameCodec.swift
//  SMCController
//
//  Length-prefixed binary-property-list framing used only by the local
//  unsigned helper session.
//

import Foundation

enum LocalHelperFrameError: LocalizedError, Equatable {
    case invalidHeader
    case emptyPayload
    case payloadTooLarge(Int)
    case invalidPropertyList

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "The local helper returned an invalid frame header."
        case .emptyPayload:
            return "The local helper returned an empty frame."
        case .payloadTooLarge(let size):
            return "The local helper frame is too large (\(size) bytes)."
        case .invalidPropertyList:
            return "The local helper returned an invalid binary property list."
        }
    }
}

struct LocalHelperFrameCodec {
    nonisolated static let maximumPayloadSize = 64 * 1024
    nonisolated static let headerSize = 4

    nonisolated static func framedPropertyList(_ dictionary: [String: Any]) throws -> Data {
        let payload = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .binary,
            options: 0
        )
        return try frame(payload: payload)
    }

    nonisolated static func frame(payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw LocalHelperFrameError.emptyPayload }
        guard payload.count <= maximumPayloadSize else {
            throw LocalHelperFrameError.payloadTooLarge(payload.count)
        }

        let length = UInt32(payload.count)
        var frame = Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ])
        frame.append(payload)
        return frame
    }

    nonisolated static func payloadLength(from header: Data) throws -> Int {
        guard header.count == headerSize else { throw LocalHelperFrameError.invalidHeader }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0 else { throw LocalHelperFrameError.emptyPayload }
        guard length <= maximumPayloadSize else {
            throw LocalHelperFrameError.payloadTooLarge(Int(length))
        }
        return Int(length)
    }

    nonisolated static func propertyListDictionary(from payload: Data) throws -> [String: Any] {
        guard payload.count >= 8,
              payload.prefix(8).elementsEqual(Data("bplist00".utf8)),
              payload.count <= maximumPayloadSize,
              let dictionary = try PropertyListSerialization.propertyList(
                from: payload,
                options: [],
                format: nil
              ) as? [String: Any] else {
            throw LocalHelperFrameError.invalidPropertyList
        }
        return dictionary
    }
}
