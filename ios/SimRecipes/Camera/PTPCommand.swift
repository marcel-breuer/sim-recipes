import Foundation

struct PTPCommand: Equatable, Sendable {
    static func getDeviceInfo(transactionID: UInt32) -> PTPCommand {
        PTPCommand(code: 0x1001, transactionID: transactionID)
    }

    static func getDevicePropValue(propertyCode: UInt16, transactionID: UInt32) -> PTPCommand {
        PTPCommand(
            code: 0x1015,
            transactionID: transactionID,
            parameters: [UInt32(propertyCode)]
        )
    }

    let code: UInt16
    let transactionID: UInt32
    let parameters: [UInt32]

    init(code: UInt16, transactionID: UInt32, parameters: [UInt32] = []) {
        self.code = code
        self.transactionID = transactionID
        self.parameters = parameters
    }

    var encoded: Data {
        var data = Data()
        data.appendLittleEndian(UInt32(12 + parameters.count * 4))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(code)
        data.appendLittleEndian(transactionID)
        parameters.forEach { data.appendLittleEndian($0) }
        return data
    }
}

struct PTPResponseHeader: Equatable, Sendable {
    static let responseContainerType: UInt16 = 3
    static let successResponseCode: UInt16 = 0x2001

    let length: UInt32
    let type: UInt16
    let responseCode: UInt16
    let transactionID: UInt32

    init(length: UInt32, type: UInt16, responseCode: UInt16, transactionID: UInt32) {
        self.length = length
        self.type = type
        self.responseCode = responseCode
        self.transactionID = transactionID
    }

    init?(data: Data) {
        guard data.count >= 12,
              let length = data.readLittleEndianUInt32(at: 0),
              let type = data.readLittleEndianUInt16(at: 4),
              let responseCode = data.readLittleEndianUInt16(at: 6),
              let transactionID = data.readLittleEndianUInt32(at: 8),
              length >= 12,
              Int(length) <= data.count,
              type == Self.responseContainerType else {
            return nil
        }

        self.length = length
        self.type = type
        self.responseCode = responseCode
        self.transactionID = transactionID
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }

    func readLittleEndianUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else {
            return nil
        }

        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func readLittleEndianUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else {
            return nil
        }

        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}

struct PTPTransaction: Equatable, Sendable {
    let header: PTPResponseHeader
    let data: Data
}
