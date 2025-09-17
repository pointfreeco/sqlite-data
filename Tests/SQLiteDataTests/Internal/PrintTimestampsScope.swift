#if canImport(CloudKit)
  import CloudKit
  import Testing

  struct _PrintTimestampsScope: SuiteTrait, TestScoping, TestTrait {
    let printTimestamps: Bool
    init(_ printTimestamps: Bool = true) {
      self.printTimestamps = printTimestamps
    }

    func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @Sendable () async throws -> Void
    ) async throws {
      try await CKRecord.$printTimestamps.withValue(true) {
        try await function()
      }
    }
  }

  extension Trait where Self == _PrintTimestampsScope {
    static var printTimestamps: Self { Self() }
    static func printTimestamps(_ printTimestamps: Bool) -> Self {
      Self(printTimestamps)
    }
  }
#endif
