package struct AnyHashableSendable: Hashable, Sendable {
  package let base: any Hashable & Sendable

  @_disfavoredOverload
  package init(_ base: any Hashable & Sendable) {
    self.init(base)
  }

  package init(_ base: some Hashable & Sendable) {
    if let base = base as? AnyHashableSendable {
      self = base
    } else {
      self.base = base
    }
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    AnyHashable(lhs.base) == AnyHashable(rhs.base)
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(base)
  }
}
