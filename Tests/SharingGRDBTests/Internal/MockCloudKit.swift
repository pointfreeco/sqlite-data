import CloudKit
import ConcurrencyExtras
import CustomDump
import SharingGRDBCore

final class MockSyncEngine: CKSyncEngineProtocol {
  let _engineState: LockIsolated<any CKSyncEngineStateProtocol>
  init(engineState: any CKSyncEngineStateProtocol) {
    self._engineState = LockIsolated(engineState)
  }
  var engineState: any CKSyncEngineStateProtocol {
    _engineState.withValue(\.self)
  }
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
  }
}

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
