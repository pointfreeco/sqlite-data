#if SQLiteDataTagged
  import Tagged

  extension Tagged: IdentifierStringConvertible where RawValue: IdentifierStringConvertible {
    public init?(rawIdentifier: String) {
      guard let rawValue = RawValue(rawIdentifier: rawIdentifier) else { return nil }
      self.init(rawValue)
    }

    public var rawIdentifier: String {
      rawValue.rawIdentifier
    }
  }
#endif
