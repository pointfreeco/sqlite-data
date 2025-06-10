import CloudKit
import SharingGRDB
import SharingGRDB
import SwiftUI
import SwiftUINavigation

struct CountersListView: View {
  @FetchAll var counters: [Counter]
  @FetchAll var sharedCounters: [CounterWithShare]
  @Dependency(\.defaultDatabase) var database
  @State var confirmDeletion: Counter?

  init() {
    _counters = FetchAll(Counter.nonShared)
    _sharedCounters = FetchAll(
      Counter.withShare
        .select {
          CounterWithShare.Columns(
            counter: $0,
            share: #sql("\($1.share)")
          )
        }
    )
  }

  @Selection
  struct CounterWithShare {
    let counter: Counter
    @Column(as: CKShare.ShareDataRepresentation.self)
    let share: CKShare
  }

  var body: some View {
    List {
      if !counters.isEmpty {
        Section {
          ForEach(counters) { counter in
            CounterRow(counter: counter)
              .buttonStyle(.borderless)
          }
          .onDelete { indexSet in
            withErrorReporting {
              try database.write { db in
                for index in indexSet {
                  try Counter.find(counters[index].id).delete()
                    .execute(db)
                }
              }
            }
          }
        } header: {
          Text("Counters")
        }
      }
      if !sharedCounters.isEmpty {
        Section {
          ForEach(sharedCounters, id: \.counter.id) { counterWithShare in
            CounterRow(counter: counterWithShare.counter)
              .buttonStyle(.borderless)
              .swipeActions {
                Button("Delete") {
                  confirmDeletion = counterWithShare.counter
                }
                .tint(.red)
              }
          }
        } header: {
          Text("Shared counters")
        }
        .alert(item: $confirmDeletion) { counter in
          Text("Delete shared counter?")
        } actions: { counter in
          Button("Delete", role: .destructive) {
            withErrorReporting {
              try database.write { db in
                try Counter.find(counter.id).delete()
                  .execute(db)
              }
            }
          }
        } message: { counter in
          Text("If you delete this counter, other people will no longer have access to it.")
        }
      }
    }
    .navigationTitle("Counters")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add") {
          withErrorReporting {
            try database.write { db in
              try Counter.insert(Counter.Draft())
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
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine
  @State var sharedRecord: SharedRecord?

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
            await withErrorReporting {
              sharedRecord = try await syncEngine.share(record: counter) { share in
                share[CKShare.SystemFieldKey.title] = "Join my counter!"
              }
            }
          }
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
    }
#if canImport(UIKit)
    .sheet(item: $sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
    }
    #endif
  }
}
