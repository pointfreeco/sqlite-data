#if canImport(CloudKit)
  import CloudKit
  import Testing
  import SQLiteData

  struct _PrepareDatabaseTrait: SuiteTrait, TestScoping, TestTrait {
    @TaskLocal static var prepareDatabase: @Sendable (UserDatabase) async throws -> Void =
      { _ in }
    let prepareDatabase: @Sendable (UserDatabase) async throws -> Void
    init(prepareDatabase: @escaping @Sendable (UserDatabase) async throws -> Void = { _ in }) {
      self.prepareDatabase = prepareDatabase
    }
    func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: () async throws -> Void
    ) async throws {
      try await Self.$prepareDatabase.withValue(prepareDatabase) {
        try await function()
      }
    }
  }

  extension Trait where Self == _PrepareDatabaseTrait {
    static func prepareDatabase(
      _ prepareDatabase: @escaping @Sendable (UserDatabase) async throws -> Void
    ) -> Self {
      .init(prepareDatabase: prepareDatabase)
    }
  }

  struct _StartImmediatelyTrait: SuiteTrait, TestScoping, TestTrait {
    @TaskLocal static var startImmediately = true
    let startImmediately: Bool
    init(startImmediately: Bool = true) {
      self.startImmediately = startImmediately
    }
    func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: () async throws -> Void
    ) async throws {
      try await Self.$startImmediately.withValue(startImmediately) {
        try await function()
      }
    }
  }

  extension Trait where Self == _StartImmediatelyTrait {
    static func startImmediately(_ startImmediately: Bool) -> Self {
      .init(startImmediately: startImmediately)
    }
  }

  struct _AttachMetadatabaseTrait: SuiteTrait, TestScoping, TestTrait {
    @TaskLocal static var attachMetadatabase = false
    let attachMetadatabase: Bool
    init(attachMetadatabase: Bool = false) {
      self.attachMetadatabase = attachMetadatabase
    }
    func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: () async throws -> Void
    ) async throws {
      try await Self.$attachMetadatabase.withValue(attachMetadatabase) {
        try await function()
      }
    }
  }

  extension Trait where Self == _AttachMetadatabaseTrait {
    static var attachMetadatabase: Self { .init(attachMetadatabase: true) }
    static func attachMetadatabase(_ attachMetadatabase: Bool) -> Self {
      .init(attachMetadatabase: attachMetadatabase)
    }
  }

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
