import CloudKit
import SQLiteData
import SwiftUI

let initialAssetSize = 10

struct CountersListView: View {
  @FetchAll(
    Counter
      .leftJoin(CounterAsset.all) { $0.id.eq($1.counterID) }
      .leftJoin(SyncMetadata.all) { $0.syncMetadataID.eq($2.id) }
      .select {
        Row.Columns(counter: $0, counterAsset: $1, isShared: $2.isShared.ifnull(false))
      }
  ) var rows
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  @Selection struct Row {
    let counter: Counter
    let counterAsset: CounterAsset?
    let isShared: Bool
  }

  var body: some View {
    List {
      if !rows.isEmpty {
        Section {
          ForEach(rows, id: \.counter.id) { row in
            CounterRow(row: row)
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
          Task {
            withErrorReporting {
              try database.write { db in
                let counterID = try Counter.insert {
                  Counter.Draft()
                }.returning(\.id)
                  .fetchOne(db)!
                try CounterAsset.insert {
                  CounterAsset(counterID: counterID, assetData: Data(count: initialAssetSize))
                }.execute(db)
              }
            }
          }
        }
      }
    }
  }

  func deleteRows(at indexSet: IndexSet) {
    withErrorReporting {
      try database.write { db in
        for index in indexSet {
          try Counter.find(rows[index].counter.id).delete()
            .execute(db)
        }
      }
    }
  }
}

struct CounterRow: View {
  let row: CountersListView.Row
  @State var sharedRecord: SharedRecord?
  @State var updateAssetCount = 0
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  var body: some View {
    VStack {
      HStack {
        if row.isShared {
          Image(systemName: "network")
        }
        Text("\(row.counter.count)")
        Button("-") {
          decrementButtonTapped()
        }
        Button("+") {
          incrementButtonTapped()
        }
        Spacer()
        if let assetData = row.counterAsset?.assetData {
          Text("Asset: \(assetData.count) bytes")
        } else {
          Text("<no asset>").foregroundStyle(.red)
        }
        Spacer()
        Button("Update asset") {
          updateAssetCount += 1
          updateAssetButtonTapped()
        }
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
      sharedRecord = try await syncEngine.share(record: row.counter) { share in
        share[CKShare.SystemFieldKey.title] = "Join my counter!"
      }
    }
  }

  func decrementButtonTapped() {
    withErrorReporting {
      try database.write { db in
        try Counter.find(row.counter.id).update {
          $0.count -= 1
        }
        .execute(db)
      }
    }
  }

  func incrementButtonTapped() {
    withErrorReporting {
      try database.write { db in
        try Counter.find(row.counter.id).update {
          $0.count += 1
        }
        .execute(db)
      }
    }
  }
  
  func updateAssetButtonTapped() {
    withErrorReporting {
      let sizeInBytes = initialAssetSize + updateAssetCount
      let assetData = Data(count: sizeInBytes)
      try database.write { db in
        // This delete isn't strictly necessary, but it's
        // what causes the data loss
        try CounterAsset
          .where { $0.counterID.eq(row.counter.id) }
          .delete()
          .execute(db)
        
        try CounterAsset.upsert {
          CounterAsset(counterID: row.counter.id, assetData: assetData)
        }.execute(db)
      }
    }
  }
}

#Preview {
  let _ = try! prepareDependencies {
    try $0.bootstrapDatabase()
    try? $0.defaultDatabase.seedSampleData()
  }
  NavigationStack {
    CountersListView()
  }
}
