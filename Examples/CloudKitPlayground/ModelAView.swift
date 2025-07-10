import CloudKit
import SharingGRDB
import SwiftUI

struct ModelAView: View {
  @FetchAll var models: [ModelA]
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.defaultSyncEngine) var syncEngine

  @State var sharedRecord: SharedRecord?

  var body: some View {
    List {
      ForEach(models) { model in
        HStack {
          Button("-") {
            withErrorReporting {
              try database.write { db in
                try ModelA.find(model.id).update { $0.count -= 1 }.execute(db)
              }
            }
          }
          Text("\(model.count)")
          Button("+") {
            withErrorReporting {
              try database.write { db in
                try ModelA.find(model.id).update { $0.count += 1 }.execute(db)
              }
            }
          }
          Spacer()
          NavigationLink("Go") {
            ModelBView(modelA: model)
          }
          Spacer()
          Button {
            Task {
              sharedRecord = try await syncEngine.share(record: model) { share in
                share[CKShare.SystemFieldKey.title] = "Join my ModelA(\(model.count))"
              }
            }
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
        }
        .buttonStyle(.plain)
      }
      .onDelete { indexSet in
        for index in indexSet {
          withErrorReporting {
            try database.write { db in
              try ModelA.find(models[index].id).delete().execute(db)
            }
          }
        }
      }
    }
    .sheet(item: $sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
    }
    .toolbar {
      Button("Add") {
        withErrorReporting {
          try database.write { db in
            try ModelA.insert { ModelA.Draft() }.execute(db)
          }
        }
      }
    }
  }
}
