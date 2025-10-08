import SQLiteData
import SwiftUI

extension Color {
  nonisolated public struct HexRepresentation: nonisolated QueryRepresentable {
    nonisolated public var queryOutput: Color
    nonisolated public init(queryOutput: Color) {
      self.queryOutput = queryOutput
    }
    nonisolated public init(hexValue: Int64) {
      self.init(
        queryOutput: Color(
          red: Double((hexValue >> 24) & 0xFF) / 0xFF,
          green: Double((hexValue >> 16) & 0xFF) / 0xFF,
          blue: Double((hexValue >> 8) & 0xFF) / 0xFF,
          opacity: Double(hexValue & 0xFF) / 0xFF
        )
      )
    }
    nonisolated public var hexValue: Int64? {
      guard let components = UIColor(queryOutput).cgColor.components
      else { return nil }
      let r = Int64(components[0] * 0xFF) << 24
      let g = Int64(components[1] * 0xFF) << 16
      let b = Int64(components[2] * 0xFF) << 8
      let a = Int64((components.indices.contains(3) ? components[3] : 1) * 0xFF)
      return r | g | b | a
    }
  }
}

extension Color.HexRepresentation: nonisolated QueryBindable {
  nonisolated public init?(queryBinding: StructuredQueriesCore.QueryBinding) {
    guard case .int(let hexValue) = queryBinding else { return nil }
    self.init(hexValue: hexValue)
  }
  nonisolated public var queryBinding: QueryBinding {
    guard let hexValue else {
      struct InvalidColor: Error {}
      return .invalid(InvalidColor())
    }
    return .int(hexValue)
  }
}

extension Color.HexRepresentation: nonisolated QueryDecodable {
  nonisolated public init(decoder: inout some QueryDecoder) throws {
    try self.init(hexValue: Int64(decoder: &decoder))
  }
}
