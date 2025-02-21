import SharingGRDB
import SwiftUI

struct TagsView: View {
  @SharedReader(.fetch(Tags())) var tags = Tags.Value()
  @Binding var selectedTags: [Tag]

  @Environment(\.dismiss) var dismiss

  var body: some View {
    Form {
      let selectedTagIDs = Set(selectedTags.map(\.id))
      if !tags.top.isEmpty {
        Section {
          ForEach(tags.top, id: \.id) { tag in
            TagView(
              isSelected: selectedTagIDs.contains(tag.id),
              selectedTags: $selectedTags,
              tag: tag
            )
          }
        } header: {
          Text("Top tags")
        }
      }
      if !tags.rest.isEmpty {
        Section {
          ForEach(tags.rest, id: \.id) { tag in
            TagView(
              isSelected: selectedTagIDs.contains(tag.id),
              selectedTags: $selectedTags,
              tag: tag
            )
          }
        }
      }
    }
    .toolbar {
      ToolbarItem {
        Button("Done") { dismiss() }
      }
    }
    .navigationTitle(Text("Tags"))
  }

  struct Tags: FetchKeyRequest {
    func fetch(_ db: Database) throws -> Value {
      let top = try Tag.fetchAll(
        db,
        sql: """
          SELECT "tags".*, count("reminders"."id")
          FROM "tags"
          LEFT JOIN "remindersTags" 
            ON "tags"."id" = "remindersTags"."tagID"
          LEFT JOIN "reminders" 
            ON "remindersTags"."reminderID" = "reminders"."id"
          GROUP BY "tags"."id"
          HAVING count("reminders"."id") > 0
          ORDER BY count("reminders"."id") DESC, "name"
          LIMIT 3
          """)
      let rest = try Tag.fetchAll(
        db,
        SQLRequest(literal: """
          SELECT "tags".*
          FROM "tags"
          WHERE "id" NOT IN \(top.compactMap(\.id))
          ORDER BY "name"
          """)
      )
      return Value(rest: rest, top: top)
    }
    struct Value {
      var rest: [Tag] = []
      var top: [Tag] = []
    }
  }
}

private struct TagView: View {
  let isSelected: Bool
  @Binding var selectedTags: [Tag]
  let tag: Tag

  var body: some View {
    Button {
      if isSelected {
        selectedTags.removeAll(where: { $0.id == tag.id })
      } else {
        selectedTags.append(tag)
      }
    } label: {
      HStack {
        if isSelected {
          Image.init(systemName: "checkmark")
        }
        Text(tag.name)
      }
    }
    .tint(isSelected ? .blue : .black)
  }
}

#Preview {
  @Previewable @State var tags: [Tag] = []
  let _ = prepareDependencies {
    $0.defaultDatabase = try! Reminders.appDatabase(inMemory: true)
  }

  TagsView(selectedTags: $tags)
}
