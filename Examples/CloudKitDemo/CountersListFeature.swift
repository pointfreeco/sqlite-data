import CloudKit
import SQLiteData
import SwiftData
import SwiftUI
import SwiftUINavigation

struct CountersListView: View {
  @FetchAll var counters: [Counter]
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  var body: some View {
    List {
      if !counters.isEmpty {
        Section {
          ForEach(counters) { counter in
            CounterRow(counter: counter)
              .buttonStyle(.borderless)
          }
          .onDelete { indexSet in
            deleteRows(at: indexSet)
          }
        }
      }
    }
    .navigationTitle("Counters")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add") {
          withErrorReporting {
            try database.write { db in
              try Counter.insert { Counter.Draft() }
                .execute(db)
            }
          }
        }
      }
      ToolbarItem {
        Button("Trigger") {
          Task { await trigger() }
        }
      }
    }
  }

func trigger() async {
  await withErrorReporting {
    // Step 1: Create a new counter
    let newCounter = try await database.write { db in
      try Counter.insert { Counter.Draft() }
        .returning(\.self)
        .fetchOne(db)!
    }

    // Step 2: Force sending all data to iCloud
    try await syncEngine.sendChanges()

    // Step 3: Grab the CKRecord for the newly inserted counter
    let newCounterLastKnownServerRecord = try await database.read { db in
      try SyncMetadata.find(newCounter.syncMetadataID).select(\.lastKnownServerRecord)
        .fetchOne(db)!!
    }

    // Step 4: Make a change to the counter directly on iCloud
    let container = CKContainer(identifier: ModelConfiguration(groupContainer: .automatic).cloudKitContainerIdentifier!)
    let serverCounter = try await container.privateCloudDatabase.record(for: newCounterLastKnownServerRecord.recordID)
    serverCounter.encryptedValues["count"] = Int.random(in: 1...1_000)
    let (saveResults, _) = try await container.privateCloudDatabase.modifyRecords(saving: [serverCounter], deleting: [])

    // Step 5: Make two changes to the local database: 1) decrement any counter besides the one
    //         created above (should succeed), and 2) increment the counter just created (should
    //         fail due to conflict)
    try await database.write { db in
      try Counter
        .where { $0.id.neq(newCounter.id) }
        .update { $0.count -= 1 }
        .execute(db)
      try Counter
        .find(newCounter.id)
        .update { $0.count += 1 }
        .execute(db)
    }

    try await syncEngine.sendChanges()
  }
}

  func deleteRows(at indexSet: IndexSet) {
    withErrorReporting {
      try database.write { db in
        for index in indexSet {
          try Counter.find(counters[index].id).delete()
            .execute(db)
        }
      }
    }
  }
}

struct CounterRow: View {
  let counter: Counter
  @State var sharedRecord: SharedRecord?
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  var body: some View {
    VStack {
      HStack {
        Text("\(counter.count)")
        Button("-") {
          decrementButtonTapped()
        }
        Button("+") {
          incrementButtonTapped()
        }
        Spacer()
        Button {
          shareButtonTapped()
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
      }
    }
    .sheet(item: $sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
    }
  }

  func shareButtonTapped() {
    Task {
      sharedRecord = try await syncEngine.share(record: counter) { share in
        share[CKShare.SystemFieldKey.title] = "Join my counter!"
      }
    }
  }

  func decrementButtonTapped() {
    withErrorReporting {
      try database.write { db in
        try Counter.find(counter.id).update {
          $0.count -= 1
        }
        .execute(db)
      }
    }
  }

  func incrementButtonTapped() {
    withErrorReporting {
      try database.write { db in
        try Counter.find(counter.id).update {
          $0.count += 1
        }
        .execute(db)
      }
    }
  }
}
