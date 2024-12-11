import SharingGRDB
import SwiftUI

struct SwiftDataTemplateView: SwiftUICaseStudy {
  let readMe = """
    This case study recreates the default SwiftData app that is used when creating a brand new
    Xcode SwiftData project.
    """
  let caseStudyTitle = "SwiftData Template"

  @Dependency(\.defaultDatabase) private var database
  @SharedReader(.fetch(Items(), animation: .default)) private var items

  var body: some View {
    NavigationStack {
      List {
        ForEach(items, id: \.id) { item in
          NavigationLink {
            Text(
              "Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))"
            )
          } label: {
            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
          }
        }
        .onDelete(perform: deleteItems)
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          EditButton()
        }
        ToolbarItem {
          Button(action: addItem) {
            Label("Add Item", systemImage: "plus")
          }
        }
      }
    }
  }

  private func addItem() {
    withErrorReporting {
      try database.write { db in
        _ = try Item(timestamp: Date()).inserted(db)
      }
    }
  }

  private func deleteItems(offsets: IndexSet) {
    withErrorReporting {
      try database.write { db in
        _ = try Item.deleteAll(db, keys: offsets.map { items[$0].id })
      }
    }
  }

  private struct Items: FetchKeyRequest {
    func fetch(_ db: Database) throws -> [Item] {
      try Item.order(Column("timestamp").desc).fetchAll(db)
    }
  }
}

private struct Item: Codable, Hashable, FetchableRecord, MutablePersistableRecord {
  var id: Int64?
  var timestamp: Date
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var swiftDataTemplateDatabase: Self {
    let databaseQueue = try! DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create items table") { db in
      try db.create(table: Item.databaseTableName) { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("timestamp", .datetime).notNull()
      }
    }
    try! migrator.migrate(databaseQueue)
    return databaseQueue
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = .swiftDataTemplateDatabase
  }
  CaseStudyView {
    SwiftDataTemplateView()
  }
}
