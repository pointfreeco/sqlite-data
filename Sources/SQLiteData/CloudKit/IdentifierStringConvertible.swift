import Foundation

/// A type that can be represented by a string identifier.
///
/// A requirement of tables synchronized to CloudKit using a ``SyncEngine``. You should generally
/// identify tables using Foundation's `UUID` type.
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

extension String: IdentifierStringConvertible {}

extension Substring: IdentifierStringConvertible {}

extension UUID: IdentifierStringConvertible {
  public init?(rawIdentifier: String) {
    self.init(uuidString: rawIdentifier)
  }
  public var rawIdentifier: String {
    description.lowercased()
  }
}

@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Bool: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Character: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Double: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Float: IdentifierStringConvertible {}
#if !(arch(i386) || arch(x86_64))
  @available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
  @available(*, deprecated, message: "Prefer globally unique identifiers.")
  extension Float16: IdentifierStringConvertible {}
#endif
#if !(os(Windows) || os(Android) || ($Embedded && !os(Linux) && !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS)))) && (arch(i386) || arch(x86_64))
  extension Float80: IdentifierStringConvertible {}
#endif
extension Int: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, *)
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Int128: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Int16: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Int32: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Int64: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Int8: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension UInt: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, *)
extension UInt128: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension UInt16: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension UInt32: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension UInt64: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension UInt8: IdentifierStringConvertible {}
@available(*, deprecated, message: "Prefer globally unique identifiers.")
extension Unicode.Scalar: IdentifierStringConvertible {}
