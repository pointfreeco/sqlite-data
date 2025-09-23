import Foundation

/// A type that can be represented by a string identifier.
///
/// A requirement of tables synchronized to CloudKit using a ``SyncEngine``. You should generally
/// identify tables using Foundation's `UUID` type or another globally unique identifier. It is
/// not appropriate to conform simple integer types to this protocol.
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
