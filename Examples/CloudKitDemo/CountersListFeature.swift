import CloudKit
import SQLiteData
import SwiftUI

struct CountersListView: View {
  @FetchAll(
    Counter
      .leftJoin(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
      .select {
        Row.Columns(counter: $0, isShared: $1.isShared.ifnull(false))
      },
    sectionBy: { _, metadata in
      Case()
        .when(metadata.isShared.eq(true), then: "Shared")
        .else("Private")
        .desc()
    }
  )
  var rows

  @State var sharedRecord: SharedRecord?

  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  @Selection struct Row {
    let counter: Counter
    let isShared: Bool
  }

  var body: some View {
    List {
      ForEach($rows.sections) { section in
        Section(section.name ?? "Private") {
          ForEach(section, id: \.counter.id) { row in
            CounterRow(row: row) {
              shareButtonTapped(row: row)
            }
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
    .sheet(item: $sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
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

  func shareButtonTapped(row: Row) {
    _ = Task {
      sharedRecord = try await syncEngine.share(record: row.counter) { share in
        share[CKShare.SystemFieldKey.title] = "Join my counter!"
      }
    }
  }
}

struct CounterRow: View {
  let row: CountersListView.Row
  let onShare: () -> Void
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
          onShare()
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
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
    try? $0.defaultDatabase.seedSampleData()
  }
  NavigationStack {
    CountersListView()
  }
}
