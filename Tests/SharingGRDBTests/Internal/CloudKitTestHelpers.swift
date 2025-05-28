import CloudKit
import ConcurrencyExtras
import CustomDump
import SharingGRDBCore

extension CKRecord.ID {
  convenience init(_ id: UUID) {
    self.init(
      recordName: id.uuidString.lowercased(),
      zoneID: SyncEngine.defaultZone.zoneID
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
final class MockSyncEngine: CKSyncEngineProtocol {
  private let _state: LockIsolated<MockSyncEngineState>
  private let _fetchChangesScopes = LockIsolated<Set<CKSyncEngine.FetchChangesOptions.Scope>>([])
  init(state: MockSyncEngineState) {
    self._state = LockIsolated(state)
  }
  var state: MockSyncEngineState {
    _state.withValue(\.self)
  }
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
    _ = _fetchChangesScopes.withValue { $0.insert(options.scope) }
  }

  func assertFetchChangesScopes(
    _ scopes: Set<CKSyncEngine.FetchChangesOptions.Scope>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _fetchChangesScopes.withValue {
      expectNoDifference(
        scopes,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
final class MockSyncEngineState: CKSyncEngineStateProtocol {
  private let _pendingRecordZoneChanges = LockIsolated<Set<CKSyncEngine.PendingRecordZoneChange>>([])
  private let _pendingDatabaseChanges = LockIsolated<Set<CKSyncEngine.PendingDatabaseChange>>([])
  private let fileID: StaticString
  private let filePath: StaticString
  private let line: UInt
  private let column: UInt

  init(
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    self.fileID = fileID
    self.filePath = filePath
    self.line = line
    self.column = column
  }

  func assertPendingRecordZoneChanges(
    _ changes: Set<CKSyncEngine.PendingRecordZoneChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingRecordZoneChanges.withValue {
      expectNoDifference(
        changes,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  func assertPendingDatabaseChanges(
    _ changes: Set<CKSyncEngine.PendingDatabaseChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingDatabaseChanges.withValue {
      expectNoDifference(
        changes,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.formUnion(pendingRecordZoneChanges)
    }
  }
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.subtract(pendingRecordZoneChanges)
    }
  }
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.formUnion(pendingDatabaseChanges)
    }
  }
  func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.subtract(pendingDatabaseChanges)
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine.FetchChangesOptions.Scope: @retroactive Hashable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.all, .all):
      return true
    case (.allExcluding(let lhs), .allExcluding(let rhs)):
      return lhs == rhs
    case (.zoneIDs(let lhs), .zoneIDs(let rhs)):
      return lhs == rhs
    case (.all, _), (.allExcluding, _), (.zoneIDs, _):
      return false
    @unknown default:
      return false
    }
  }
  public func hash(into hasher: inout Hasher) {
    switch self {
    case .all:
      hasher.combine(0)
    case .allExcluding(let zoneIDs):
      hasher.combine(1)
      hasher.combine(zoneIDs)
    case .zoneIDs(let zoneIDs):
      hasher.combine(2)
      hasher.combine(zoneIDs)
    @unknown default:
      hasher.combine(3)
    }
  }
}
