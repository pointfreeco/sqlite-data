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
      let top = try Tag
        .group(by: \.id)
        .join(ReminderTag.all()) { $0.id.eq($1.tagID)}
        .join(Reminder.all()) { $1.reminderID.eq($2.id)}
        .having { $2.id.count().gt(0) }
        .order { ($2.id.count().desc(), $0.name) }
        .limit(3)
        .select { tags, _, _ in tags }
        .fetchAll(db)

      let rest = try Tag
        .where { !$0.id.in(top.compactMap(\.id)) }
        .fetchAll(db)

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
  let _ = try! prepareDependencies {
    $0.defaultDatabase = try Reminders.appDatabase()
  }

  TagsView(selectedTags: $tags)
}
