import Foundation

public protocol IdentifierStringConvertible {
  init?(rawIdentifier: String)
  var rawIdentifier: String { get }
}

extension IdentifierStringConvertible where Self: CustomStringConvertible {
  public var rawIdentifier: String { description }
}

extension IdentifierStringConvertible where Self: LosslessStringConvertible {
  public init?(rawIdentifier: String) {
    self.init(rawIdentifier)
  }
}

extension Bool: IdentifierStringConvertible {}
extension Character: IdentifierStringConvertible {}
extension Double: IdentifierStringConvertible {}
extension Float: IdentifierStringConvertible {}
#if !(arch(i386) || arch(x86_64))
  @available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
  extension Float16: IdentifierStringConvertible {}
#endif
#if !(os(Windows) || os(Android) || ($Embedded && !os(Linux) && !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS)))) && (arch(i386) || arch(x86_64))
  extension Float80: IdentifierStringConvertible {}
#endif
extension Int: IdentifierStringConvertible {}
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, *)
extension Int128: IdentifierStringConvertible {}
extension Int16: IdentifierStringConvertible {}
extension Int32: IdentifierStringConvertible {}
extension Int64: IdentifierStringConvertible {}
extension Int8: IdentifierStringConvertible {}
extension String: IdentifierStringConvertible {}
extension Substring: IdentifierStringConvertible {}
extension UInt: IdentifierStringConvertible {}
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, *)
extension UInt128: IdentifierStringConvertible {}
extension UInt16: IdentifierStringConvertible {}
extension UInt32: IdentifierStringConvertible {}
extension UInt64: IdentifierStringConvertible {}
extension UInt8: IdentifierStringConvertible {}
extension Unicode.Scalar: IdentifierStringConvertible {}

extension UUID: IdentifierStringConvertible {
  public init?(rawIdentifier: String) {
    self.init(uuidString: rawIdentifier)
  }
  public var rawIdentifier: String {
    description.lowercased()
  }
}
