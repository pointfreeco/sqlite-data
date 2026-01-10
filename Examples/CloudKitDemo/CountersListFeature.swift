import CloudKit
import SQLiteData
import SwiftUI

struct CountersListView: View {
  @FetchAll(
    Counter
      .leftJoin(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
      .select {
        Row.Columns(counter: $0, isShared: $1.isShared.ifnull(false))
      }
  ) var rows
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  @Selection struct Row {
    let counter: Counter
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
                try Counter.insert {
                  Counter.Draft()
                }
                .execute(db)
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
}

#Preview {
  let _ = try! prepareDependencies {
    try $0.bootstrapDatabase()
  }
  NavigationStack {
    CountersListView()
  }
}
