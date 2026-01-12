import SQLiteData
import SwiftUI
import SwiftUINavigation

struct TagsView: View {
  @Fetch(Tags()) var tags = Tags.Value()
  @Binding var selectedTags: [Tag]
  @State var editingTag: Tag.Draft?
  @State var tagTitle = ""

  @Dependency(\.defaultDatabase) var database
  @Environment(\.dismiss) var dismiss

  var body: some View {
    Form {
      let selectedTagIDs = Set(selectedTags.map(\.id))
      Section {
        Button("New tag") {
          tagTitle = ""
          editingTag = Tag.Draft()
        }
      }
      if !tags.top.isEmpty {
        Section {
          ForEach(tags.top, id: \.id) { tag in
            TagView(
              isSelected: selectedTagIDs.contains(tag.id),
              selectedTags: $selectedTags,
              tag: tag
            )
            .swipeActions {
              Button("Delete", role: .destructive) {
                deleteButtonTapped(tag: tag)
              }
              Button("Edit") {
                editButtonTapped(tag: tag)
              }
            }
          }
        } header: {
          Text("Top tags")
        }
      }
      if !tags.rest.isEmpty {
        Section {
          ForEach(tags.rest) { tag in
            TagView(
              isSelected: selectedTagIDs.contains(tag.id),
              selectedTags: $selectedTags,
              tag: tag
            )
            .swipeActions {
              Button("Delete", role: .destructive) {
                deleteButtonTapped(tag: tag)
              }
              Button("Edit") {
                editButtonTapped(tag: tag)
              }
            }
          }
        }
      }
    }
    .alert(item: $editingTag) { item in
      Text(item.title == nil ? "New tag" : "Edit tag")
    } actions: { item in
      TextField("Tag name", text: $tagTitle)
      Button("Save") {
        saveButtonTapped()
      }
      Button("Cancel", role: .cancel) {}
    }
    .toolbar {
      ToolbarItem {
        Button("Done") { dismiss() }
      }
    }
    .navigationTitle(Text("Tags"))
  }

  func deleteButtonTapped(tag: Tag) {
    withErrorReporting {
      try database.write { db in
        try Tag.find(tag.title).delete().execute(db)
      }
    }
  }

  func editButtonTapped(tag: Tag) {
    tagTitle = tag.title
    editingTag = Tag.Draft(tag)
  }

  func saveButtonTapped() {
    defer { tagTitle = "" }
    let tag = Tag(title: tagTitle)
    withErrorReporting {
      try database.write { db in
        if let existingTagTitle = editingTag?.title {
          selectedTags.removeAll(where: { $0.title == existingTagTitle })
          try Tag
            .update { $0.title = tagTitle }
            .where { $0.title.eq(existingTagTitle) }
            .execute(db)
        } else {
          try Tag.insert(or: .ignore) { tag }
            .execute(db)
        }
      }
      selectedTags.append(tag)
    }
  }

  struct Tags: FetchKeyRequest {
    func fetch(_ db: Database) throws -> Value {
      let top =
        try Tag
        .withReminders
        .having { $2.count().gt(0) }
        .order { ($2.count().desc(), $0.title) }
        .select { tag, _, _ in tag }
        .limit(3)
        .fetchAll(db)

      let rest =
        try Tag
        .where { !$0.primaryKey.in(top.map(\.primaryKey)) }
        .order(by: \.title)
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
          Image(systemName: "checkmark")
        }
        Text(tag.title)
      }
    }
    .tint(isSelected ? .accentColor : .primary)
  }
}

#Preview {
  @Previewable @State var tags: [Tag] = []
  let _ = try! prepareDependencies {
    try $0.bootstrapDatabase()
    try $0.defaultDatabase.seedSampleData()
  }
  TagsView(selectedTags: $tags)
}
