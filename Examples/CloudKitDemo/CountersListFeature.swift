import CloudKit
import SQLiteData
import SwiftUI

struct CountersListView: View {
  @FetchAll var counters: [Counter]
  @Dependency(\.defaultDatabase) var database

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
