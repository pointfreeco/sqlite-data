import SharingGRDB
import SwiftUI

struct ModelBView: View {
  let modelA: ModelA
  @FetchAll var models: [ModelB]
  @Dependency(\.defaultDatabase) var database

  init(modelA: ModelA) {
    self.modelA = modelA
    _models = FetchAll(ModelB.where { $0.modelAID.eq(modelA.id) })
  }

  var body: some View {
    List {
      ForEach(models) { model in
        HStack {
          Toggle("On? \(model.isOn ? "YES" : "NO")", isOn: Binding {
            model.isOn
          } set: { newValue in
            withErrorReporting {
              try database.write { db in
                try ModelB.find(model.id).update { $0.isOn = newValue }.execute(db)
              }
            }
          })

          Spacer()
          NavigationLink("Go") {
            ModelCView(modelB: model)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .toolbar {
      Button("Add") {
        withErrorReporting {
          try database.write { db in
            try ModelB.insert { ModelB.Draft(modelAID: modelA.id) }.execute(db)
          }
        }
      }
    }
  }
}
