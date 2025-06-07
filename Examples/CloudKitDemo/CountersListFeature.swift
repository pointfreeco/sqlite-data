import SharingGRDB
import SwiftUI

struct CountersListView: View {
  let parentCounter: Counter?
  @FetchAll var counters: [Counter]
  @Dependency(\.defaultDatabase) var database

  init(parentCounter: Counter? = nil) {
    self.parentCounter = parentCounter
    _counters = FetchAll(Counter.where { $0.parentCounterID.is(parentCounter?.id) })
  }

  var body: some View {
    List {
      ForEach(counters) { counter in
        HStack {
          NavigationLink {
            CountersListView(parentCounter: counter)
          } label: {
            Text("\(counter.count)")
          }
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
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add") {
          withErrorReporting {
            try database.write { db in
              try Counter.insert(Counter.Draft(parentCounterID: parentCounter?.id))
                .execute(db)
            }
          }
        }
      }
    }
  }
}
