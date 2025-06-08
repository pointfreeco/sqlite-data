import SharingGRDB
import SwiftUI

struct CountersListView: View {
  let parentCounter: Counter?
  @FetchAll var counters: [Counter]
  @Dependency(\.defaultDatabase) var database

  init(parentCounter: Counter? = nil) {
    self.parentCounter = parentCounter
    _counters = FetchAll(
      Counter
        .where { $0.parentCounterID.is(parentCounter?.id) }
        .order(by: \.name)
    )
  }

  var body: some View {
    List {
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
    }
    .navigationTitle(parentCounter?.name ?? "Root")
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

struct CounterRow: View {
  let counter: Counter
  @State var editedName = ""
  @FocusState var isFocused: Bool
  @Dependency(\.defaultDatabase) var database
  var body: some View {
    HStack {
      NavigationLink {
        CountersListView(parentCounter: counter)
      } label: {
        HStack {
          TextField("Name", text: $editedName)
            .focused($isFocused)
            .onSubmit { saveName() }
            .onChange(of: isFocused) { saveName() }
          Spacer()
          Text("\(counter.count)")
        }
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
    .onChange(of: counter.name, initial: true) {
      editedName = counter.name
    }
  }

  func saveName() {
    withErrorReporting {
      try database.write { db in
        try Counter
          .find(counter.id)
          .update { $0.name = editedName }
          .execute(db)
      }
    }
  }
}
