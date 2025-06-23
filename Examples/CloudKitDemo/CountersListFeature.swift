import CloudKit
import SharingGRDB
import SwiftUI
import SwiftUINavigation

struct CountersListView: View {
  @FetchAll(
    Counter
      .join(SyncMetadata.all) { $0.id.eq($1.recordPrimaryKey) }
      .where { $1.share.is(nil) }
      .select {
        Row.Columns(counter: $0, share: $1.share)
      }
  )
  var localCounters
  @FetchAll(
    Counter
      .join(SyncMetadata.all) { $0.id.eq($1.recordPrimaryKey) }
      .where { $1.share.isNot(nil) }
      .select {
        Row.Columns(counter: $0, share: $1.share)
      }
  )
  var sharedCounters
  @Dependency(\.defaultDatabase) var database
  @State var confirmDeletion: Counter?

  @Selection
  struct Row {
    let counter: Counter
    @Column(as: CKShare?.ShareDataRepresentation.self)
    let share: CKShare?
  }

  var body: some View {
    List {
      if !localCounters.isEmpty {
        Section {
          ForEach(localCounters, id: \.counter.id) { row in
            CounterRow(row: row)
              .buttonStyle(.borderless)
          }
          .onDelete { indexSet in
            withErrorReporting {
              try database.write { db in
                for index in indexSet {
                  try Counter.find(localCounters[index].counter.id).delete()
                    .execute(db)
                }
              }
            }
          }
        } header: {
          Text("Local counters")
        }
      }

      if !sharedCounters.isEmpty {
        Section {
          ForEach(sharedCounters, id: \.counter.id) { row in
            CounterRow(row: row)
              .buttonStyle(.borderless)
          }
          .onDelete { indexSet in
            withErrorReporting {
              try database.write { db in
                for index in indexSet {
                  try Counter.find(sharedCounters[index].counter.id).delete()
                    .execute(db)
                }
              }
            }
          }
        } header: {
          Text("Shared counters")
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
        Text("\(row.counter.count)")
        Button("-") {
          withErrorReporting {
            try database.write { db in
              try Counter.find(row.counter.id).update {
                $0.count -= 1
              }
              .execute(db)
            }
          }
        }
        Button("+") {
          withErrorReporting {
            try database.write { db in
              try Counter.find(row.counter.id).update {
                $0.count += 1
              }
              .execute(db)
            }
          }
        }
        Spacer()
        Button {
          Task {
            sharedRecord = try await syncEngine.share(record: row.counter) { share in
              share[CKShare.SystemFieldKey.title] = "Join my counter!"
            }
          }
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
      }

      if let share = row.share {
        Text(share.participants
          .compactMap { $0.userIdentity.nameComponents?.formatted() }
          .joined(separator: ", "))
      }
    }
    .sheet(item: $sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
    }
  }
}
