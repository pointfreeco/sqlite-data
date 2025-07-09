import SharingGRDB
import SwiftUI

struct ModelCView: View {
  let modelB: ModelB
  @FetchAll var models: [ModelC]
  @Dependency(\.defaultDatabase) var database

  init(modelB: ModelB) {
    self.modelB = modelB
    _models = FetchAll(ModelC.where { $0.modelBID.eq(modelB.id) })
  }

  var body: some View {
    List {
      ForEach(models) { model in
        HStack {
          TextField("Title", text: Binding {
            model.title
          } set: { newValue in
            withErrorReporting {
              try database.write { db in
                try ModelC.find(model.id).update { $0.title = newValue }.execute(db)
              }
            }
          })
        }
        .buttonStyle(.plain)
      }
    }
    .toolbar {
      Button("Add") {
        withErrorReporting {
          try database.write { db in
            try ModelC.insert { ModelC.Draft(modelBID: modelB.id) }.execute(db)
          }
        }
      }
    }
  }
}
