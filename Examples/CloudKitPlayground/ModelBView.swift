import SQLiteData
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
          Toggle(
            "On? \(model.isOn ? "YES" : "NO")",
            isOn: Binding {
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
      .onDelete { indexSet in
        for index in indexSet {
          withErrorReporting {
            try database.write { db in
              try ModelB.find(models[index].id).delete().execute(db)
            }
          }
        }
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
      Button("Special") {
        withErrorReporting {
          try database.write { db in
            let modelB = try ModelB.insert { ModelB.Draft(modelAID: modelA.id) }.returning(\.self)
              .fetchOne(db)
            guard let modelB
            else { return }

            for index in 1...5 {
              try ModelC
                .insert { ModelC.Draft.init(title: index.description, modelBID: modelB.id) }
                .execute(db)
            }
          }
        }
      }
    }
  }
}
