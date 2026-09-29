public import Foundation

extension UUID {
  @usableFromInline
  init?(uuidUTF8 utf8: UnsafeBufferPointer<UInt8>) {
    guard utf8.count == 36 else { return nil }
    var raw: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    let parsed = withUnsafeMutableBytes(of: &raw) { bytes in
      var index = 0
      for byteIndex in 0..<16 {
        if byteIndex == 4 || byteIndex == 6 || byteIndex == 8 || byteIndex == 10 {
          guard utf8[index] == UInt8(ascii: "-") else { return false }
          index += 1
        }
        guard let high = hexValue(utf8[index]), let low = hexValue(utf8[index + 1])
        else { return false }
        bytes[byteIndex] = high << 4 | low
        index += 2
      }
      return true
    }
    guard parsed else { return nil }
    self.init(uuid: raw)
  }

  func withLowercasedUTF8Text<R>(_ body: (UnsafePointer<CChar>, Int32) -> R) -> R {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 36) { utf8 in
      withUnsafeBytes(of: uuid) { bytes in
        var offset = 0
        for (byteIndex, byte) in bytes.enumerated() {
          if byteIndex == 4 || byteIndex == 6 || byteIndex == 8 || byteIndex == 10 {
            utf8[offset] = UInt8(ascii: "-")
            offset += 1
          }
          utf8[offset] = hexDigits[Int(byte >> 4)]
          utf8[offset + 1] = hexDigits[Int(byte & 0xF)]
          offset += 2
        }
      }
      return utf8.baseAddress!.withMemoryRebound(to: CChar.self, capacity: 36) {
        body($0, 36)
      }
    }
  }
}

private func hexValue(_ byte: UInt8) -> UInt8? {
  switch byte {
  case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
  case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
  case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
  default: nil
  }
}

private let hexDigits = Array("0123456789abcdef".utf8)
