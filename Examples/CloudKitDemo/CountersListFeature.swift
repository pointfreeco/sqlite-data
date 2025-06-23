import CloudKit
import SharingGRDB
import SwiftUI
import SwiftUINavigation

struct CountersListView: View {
  @FetchAll(
    Counter
      .join(SyncMetadata.all) { $0.id.eq($1.recordPrimaryKey) }
      .where { $1.share.is(nil) }
      .select { counter, _ in counter }
  )
  var localCounters: [Counter]
  @FetchAll(
    Counter
      .join(SyncMetadata.all) { $0.id.eq($1.recordPrimaryKey) }
      .where { $1.share.isNot(nil) }
      .select { counter, _ in counter }
  )
  var sharedCounters: [Counter]
  @Dependency(\.defaultDatabase) var database
  @State var confirmDeletion: Counter?

  var body: some View {
    List {
      if !localCounters.isEmpty {
        Section {
          ForEach(localCounters) { counter in
            CounterRow(counter: counter)
              .buttonStyle(.borderless)
          }
          .onDelete { indexSet in
            withErrorReporting {
              try database.write { db in
                for index in indexSet {
                  try Counter.find(localCounters[index].id).delete()
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
          ForEach(sharedCounters) { counter in
            CounterRow(counter: counter)
              .buttonStyle(.borderless)
          }
          .onDelete { indexSet in
            withErrorReporting {
              try database.write { db in
                for index in indexSet {
                  try Counter.find(sharedCounters[index].id).delete()
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
  let counter: Counter
  @State var sharedRecord: SharedRecord?
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  var body: some View {
    HStack {
      Text("\(counter.count)")
      Button("-") {
        withErrorReporting {
          try database.write { db in
            try Counter.find(counter.id).update {
              $0.count -= 1
            }
            .execute(db)
          }
        }
      }
      Button("+") {
        withErrorReporting {
          try database.write { db in
            try Counter.find(counter.id).update {
              $0.count += 1
            }
            .execute(db)
          }
        }
      }
      Spacer()
      Button {
        Task {
          sharedRecord = try await syncEngine.share(record: counter) { share in
            share[CKShare.SystemFieldKey.title] = "Join my counter!"
          }
        }
      } label: {
        Image(systemName: "square.and.arrow.up")
      }
    }
    .sheet(item: $sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
    }
  }
}
