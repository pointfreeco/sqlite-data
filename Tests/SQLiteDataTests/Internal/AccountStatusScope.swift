#if canImport(CloudKit)
  import CloudKit
  import Testing

  struct _AccountStatusScope: SuiteTrait, TestScoping, TestTrait {
    @TaskLocal static var accountStatus = CKAccountStatus.available

    let accountStatus: CKAccountStatus
    init(_ accountStatus: CKAccountStatus = .available) {
      self.accountStatus = accountStatus
    }

    func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @Sendable () async throws -> Void
    ) async throws {
      try await Self.$accountStatus.withValue(accountStatus) {
        try await function()
      }
    }
  }

  extension Trait where Self == _AccountStatusScope {
    static var accountStatus: Self { .init() }
    static func accountStatus(_ accountStatus: CKAccountStatus) -> Self {
      .init(accountStatus)
    }
  }
#endif
