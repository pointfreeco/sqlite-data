#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    @Suite(.attachMetadatabase(true))
    final class BidirectionalMigrationTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func basics() async throws {
        try await userDatabase.userWrite { db in
          try OldFood
            .insert {
              OldFood(
                id: UUID(0),
                dateEaten: Date(timeIntervalSince1970: 1),
                wasEaten: false
              )
              OldFood(
                id: UUID(1),
                dateEaten: Date(timeIntervalSince1970: 2),
                wasEaten: true
              )
            }
            .execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        syncEngine.stop()

        try await userDatabase.userWrite { db in
          try #sql(
            """
            ALTER TABLE "foods" 
            ADD COLUMN "actualDateEaten" TEXT
            """
          )

          .execute(db)
          try #sql(
            """
            ALTER TABLE "foods" 
            ADD COLUMN "scheduledDate" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
            """
          )
          .execute(db)

          try #sql(
            """
            UPDATE "foods"
            SET
              "scheduledDate" = "dateEaten",
              "actualDateEaten" = CASE WHEN "wasEaten" THEN "dateEaten" END
            WHERE "scheduledDate" = ''
            """
          )
          .execute(db)


          // try db.installBidirectionTriggers(for: Food.self) { … }
          // try Food.installBidirectionTriggers(db: db) { row, new in



//            row._wasEaten = new.dateEaten.isNot(nil)
//            row._dateEaten = new.dateEaten.ifnull(new.scheduledDate)
//          } back: { row, new in
//            row.dateEaten = Case().when(new._wasEaten, then: new._dateEaten)
//            row.scheduledDate = Case(row.scheduledDate)
//              .when(#sql("''"), then: new._dateEaten)
//              .else($0.scheduledDate)
//          }


          // NB: Play inserts/updates from user running new app to old columns.
          try Food.createTemporaryTrigger(
            after: .insert { new in
              Food
                .find(new.id)
                .update {
                  $0._wasEaten = new.dateEaten.isNot(nil)
                  $0._dateEaten = new.dateEaten.ifnull(new.scheduledDate)
                }
            } when: { _ in
              !SyncEngine.$isSynchronizing
            }
          )
          .execute(db)
          try Food.createTemporaryTrigger(
            after: .update {
              ($0.dateEaten, $0.scheduledDate)
            } forEachRow: { old, new in
              Food
                .find(new.id)
                .update {
                  $0._wasEaten = new.dateEaten.isNot(nil)
                  $0._dateEaten = new.dateEaten.ifnull(new.scheduledDate)
                }
            } when: { _, _ in
              !SyncEngine.$isSynchronizing
            }
          )
          .execute(db)

          // NB: Play inserts/updates from user running old app to new columns.
          try Food.createTemporaryTrigger(
            after: .insert { new in
              Food
                .find(new.id)
                .update {
                  $0.dateEaten = Case().when(new._wasEaten, then: new._dateEaten)
                  $0.scheduledDate = Case($0.scheduledDate)
                    .when(#sql("''"), then: new._dateEaten)
                    .else($0.scheduledDate)
                }
            } when: { _ in
              SyncEngine.$isSynchronizing
            }
          )
          .execute(db)
          try Food.createTemporaryTrigger(
            after: .update {
              ($0._wasEaten, $0._dateEaten)
            } forEachRow: { old, new in
              Food
                .find(new.id)
                .update {
                  $0.dateEaten = Case().when(new._wasEaten, then: new._dateEaten)
                  $0.scheduledDate = Case($0.scheduledDate)
                    .when(#sql("''"), then: new._dateEaten)
                    .else($0.scheduledDate)
                }
            } when: { _, _ in
              SyncEngine.$isSynchronizing
            }
          )
          .execute(db)
        }

        let relaunchedSyncEngine = try await SyncEngine(
          container: syncEngine.container,
          userDatabase: syncEngine.userDatabase,
          tables: syncEngine.tables
            .filter { $0.base != OldFood.self }
            + [
              SynchronizedTable(for: Food.self)
            ],
          privateTables: syncEngine.privateTables
        )
        defer { _ = relaunchedSyncEngine }

        try await userDatabase.userWrite { db in
          try expectNoDifference(
            Food.fetchAll(db),
            [
              Food(
                id: UUID(0),
                _dateEaten: Date(timeIntervalSince1970: 1),
                _wasEaten: false,
                dateEaten: nil,
                scheduledDate: Date(timeIntervalSince1970: 1)
              ),
              Food(
                id: UUID(1),
                _dateEaten: Date(timeIntervalSince1970: 2),
                _wasEaten: true,
                dateEaten: Date(timeIntervalSince1970: 2),
                scheduledDate: Date(timeIntervalSince1970: 2)
              ),
            ]
          )

          try Food
            .find(UUID(0))
            .update { $0.dateEaten = Date(timeIntervalSince1970: 3) }
            .execute(db)

          let freshFood = try #require(try Food.find(UUID(0)).fetchOne(db))
          expectNoDifference(
            freshFood,
            Food(
              id: UUID(0),
              _dateEaten: Date(timeIntervalSince1970: 3),
              _wasEaten: true,
              dateEaten: Date(timeIntervalSince1970: 3),
              scheduledDate: Date(timeIntervalSince1970: 1)
            )
          )

          try Food
            .insert {
              Food(id: UUID(2), dateEaten: nil, scheduledDate: Date(timeIntervalSince1970: 4))
            }
            .execute(db)

          let freshFood2 = try #require(try Food.find(UUID(2)).fetchOne(db))
          expectNoDifference(
            freshFood2,
            Food(
              id: UUID(2),
              _dateEaten: Date(timeIntervalSince1970: 4),
              _wasEaten: false,
              dateEaten: nil,
              scheduledDate: Date(timeIntervalSince1970: 4)
            )
          )
        }
        try await relaunchedSyncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          let foodRecord = try relaunchedSyncEngine.private.database.record(
            for: Food.recordID(for: UUID(2))
          )
          foodRecord.setValue(Date(timeIntervalSince1970: 5), forKey: "dateEaten", at: 1)
          foodRecord.setValue(true, forKey: "wasEaten", at: now)

          try await relaunchedSyncEngine
            .modifyRecords(scope: .private, saving: [foodRecord])
            .notify()

          try await userDatabase.userWrite { db in
            try expectNoDifference(
              Food.find(UUID(2)).fetchOne(db),
              Food(
                id: UUID(2),
                _dateEaten: Date(timeIntervalSince1970: 5),
                _wasEaten: true,
                dateEaten: Date(timeIntervalSince1970: 5),
                scheduledDate: Date(timeIntervalSince1970: 4)
              )
            )
          }

          let newFoodRecord = CKRecord(
            recordType: Food.tableName,
            recordID: Food.recordID(for: UUID(3))
          )
          newFoodRecord.setValue(UUID(3).uuidString, forKey: "id", at: now)
          newFoodRecord.setValue(Date(timeIntervalSince1970: 6), forKey: "dateEaten", at: 1)
          newFoodRecord.setValue(false, forKey: "wasEaten", at: 1)
          try await relaunchedSyncEngine
            .modifyRecords(scope: .private, saving: [newFoodRecord])
            .notify()

          try await userDatabase.userWrite { db in
            try expectNoDifference(
              Food.find(UUID(3)).fetchOne(db),
              Food(
                id: UUID(3),
                _dateEaten: Date(timeIntervalSince1970: 6),
                _wasEaten: false,
                dateEaten: nil,
                scheduledDate: Date(timeIntervalSince1970: 6)
              )
            )
          }
        }
      }
    }
  }

  // NB: This type would not actually exist in the new version of the app. Only 'Food' would.
  @Table("foods") struct OldFood: Equatable {
    let id: UUID
    var dateEaten: Date
    var wasEaten: Bool
  }
  @Table struct Food: Equatable {
    let id: UUID
    @Column("dateEaten") var _dateEaten: Date
    @Column("wasEaten") var _wasEaten: Bool

    @Column("actualDateEaten")
    var dateEaten: Date?
    var scheduledDate: Date
  }
  extension Food {
    init(
      id: UUID,
      dateEaten: Date? = nil,
      scheduledDate: Date
    ) {
      self.id = id
      _wasEaten = (dateEaten != nil)
      self.dateEaten = dateEaten
      _dateEaten = (dateEaten ?? scheduledDate)
      self.scheduledDate = scheduledDate
    }
  }

#endif
