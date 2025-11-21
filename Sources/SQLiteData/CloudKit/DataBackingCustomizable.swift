public protocol DataBackingCustomizable {
  func backing(for column: String) -> DataBacking
}

public enum DataBacking {
  case asset
  case inline
}
