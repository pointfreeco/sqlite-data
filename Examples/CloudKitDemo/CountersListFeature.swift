import CloudKit
import SharingGRDB
import SharingGRDB
import SwiftUI
import SwiftUINavigation

struct CountersListView: View {
  @FetchAll var counters: [Counter]
  @Dependency(\.defaultDatabase) var database
  @State var confirmDeletion: Counter?

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
  @Dependency(\.defaultDatabase) var database

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
    }
  }
}
