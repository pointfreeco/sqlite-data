import StructuredQueriesCore
import SwiftUI

extension Color {
  public struct HexRepresentation: QueryBindable, QueryRepresentable {
    public var queryOutput: Color
    public var queryBinding: QueryBinding {
      guard let components = UIColor(queryOutput).cgColor.components
      else {
        struct InvalidColor: Error {}
        return .invalid(InvalidColor())
      }
      let r = Int64(components[0] * 0xFF) << 24
      let g = Int64(components[1] * 0xFF) << 16
      let b = Int64(components[2] * 0xFF) << 8
      let a = Int64((components.indices.contains(3) ? components[3] : 1) * 0xFF)
      return .int(r | g | b | a)
    }
    public init(queryOutput: Color) {
      self.queryOutput = queryOutput
    }
    public init(decoder: inout some QueryDecoder) throws {
      let hex = try Int(decoder: &decoder)
      self.init(
        queryOutput: Color(
          red: Double((hex >> 24) & 0xFF) / 0xFF,
          green: Double((hex >> 16) & 0xFF) / 0xFF,
          blue: Double((hex >> 8) & 0xFF) / 0xFF,
          opacity: Double(hex & 0xFF) / 0xFF
        )
      )
    }
  }
}
