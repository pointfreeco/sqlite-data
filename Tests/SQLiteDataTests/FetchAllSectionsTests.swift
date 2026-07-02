import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct FetchAllSectionsTests {
  @Dependency(\.defaultDatabase) var database

  @Test func basics() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()

    #expect(reminders.map(\.id) == [1, 2, 3, 4, 5])
    #expect($reminders.sections.count == 3)
    #expect($reminders.sections.sectionNames == ["Home", "Work", "Errands"])
    #expect($reminders.sections.map(\.name) == ["Home", "Work", "Errands"])
    #expect($reminders.sections[0].map(\.title) == ["Dishes", "Laundry"])
    #expect($reminders.sections[1].map(\.title) == ["Standup", "Review"])
    #expect($reminders.sections[2].map(\.title) == ["Groceries"])
  }

  @Test func sectionOrderFollowsQueryOrder() async throws {
    @FetchAll(SectionedReminder.order { $0.category.desc() }, sectionBy: \.category) var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == ["Work", "Home", "Errands"])
  }

  @Test func optionalSectionName() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.priority) var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == ["high", "low", ""])
    #expect($reminders.sections[sectionName: ""]?.map(\.title) == ["Laundry", "Review"])
  }

  @Test func sectionLookup() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()

    let sections = $reminders.sections
    #expect(sections[sectionName: "Work"]?.map(\.title) == ["Standup", "Review"])
    #expect(sections[sectionName: "Gym"] == nil)
    #expect(sections.contains(sectionName: "Errands"))
    #expect(!sections.contains(sectionName: "Gym"))
    #expect(sections.index(ofSectionNamed: "Home") == 0)
    #expect(sections.index(ofSectionNamed: "Errands") == 2)
    #expect(sections.index(ofSectionNamed: "Gym") == nil)

    let work = try #require(sections[sectionName: "Work"])
    #expect(work.id == "Work")
    #expect(work.name == "Work")
    #expect(work.count == 2)
    #expect(work[0].title == "Standup")
  }

  @Test func observesChanges() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()
    #expect($reminders.sections.count == 3)

    try await database.write { db in
      try SectionedReminder.insert {
        SectionedReminder.Draft(title: "Squats", category: "Gym")
      }
      .execute(db)
    }
    try await $reminders.load()

    #expect(reminders.count == 6)
    #expect($reminders.sections.sectionNames == ["Home", "Work", "Errands", "Gym"])
    #expect($reminders.sections[sectionName: "Gym"]?.map(\.title) == ["Squats"])
  }

  @Test func loadStatementPreservesSectioning() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()
    #expect($reminders.sections.count == 3)

    try await $reminders.load(SectionedReminder.where { $0.category.neq("Work") }.order(by: \.id))

    #expect(reminders.map(\.title) == ["Dishes", "Groceries", "Laundry"])
    #expect($reminders.sections.sectionNames == ["Home", "Errands"])
    #expect($reminders.sections[sectionName: "Home"]?.map(\.title) == ["Dishes", "Laundry"])
  }

  @Test func emptyResults() async throws {
    @FetchAll(SectionedReminder.where { $0.id > 100 }, sectionBy: \.category) var reminders
    try await $reminders.load()

    #expect(reminders.isEmpty)
    #expect($reminders.sections.isEmpty)
    #expect($reminders.sections.sectionNames.isEmpty)
  }

  @Test func defaultWrappedValueIsSectioned() throws {
    let defaults = [
      SectionedReminder(id: 1, title: "A", category: "One"),
      SectionedReminder(id: 2, title: "B", category: "Two"),
      SectionedReminder(id: 3, title: "C", category: "One"),
    ]
    @FetchAll(
      wrappedValue: defaults,
      SectionedReminder.all,
      sectionBy: \.category,
      database: try DatabaseQueue()
    )
    var reminders

    #expect($reminders.loadError != nil)
    #expect(reminders == defaults)
    #expect($reminders.sections.sectionNames == ["One", "Two"])
    #expect($reminders.sections[0].map(\.title) == ["A", "C"])
  }

  @Test func wholeTable() async throws {
    @FetchAll(sectionBy: \SectionedReminder.category) var reminders
    try await $reminders.load()

    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == ["Home", "Work", "Errands"])
  }

  @Test func reassignment() async throws {
    @FetchAll(SectionedReminder.order(by: \.id)) var reminders
    try await $reminders.load()
    #expect(reminders.count == 5)

    $reminders = FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category)
    try await $reminders.load()
    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == ["Home", "Work", "Errands"])

    $reminders = FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.priority)
    try await $reminders.load(SectionedReminder.order(by: \.id))
    #expect($reminders.sections.sectionNames == ["high", "low", ""])

    $reminders = FetchAll(SectionedReminder.order(by: \.title))
    try await $reminders.load()
    #expect(reminders.map(\.title) == ["Dishes", "Groceries", "Laundry", "Review", "Standup"])
    #expect($reminders.sections.sectionNames == [""])
    #expect($reminders.sections[0].count == 5)
  }

  @Test func nilSectionBy() async throws {
    let sectionKeyPath: KeyPath<SectionedReminder, String>? = nil
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: sectionKeyPath) var reminders
    try await $reminders.load()

    #expect(reminders.map(\.id) == [1, 2, 3, 4, 5])
    #expect($reminders.sections.sectionNames == [""])
    #expect($reminders.sections[0].map(\.id) == [1, 2, 3, 4, 5])
  }

  @Test func nilSectionByWholeTable() async throws {
    @FetchAll(sectionBy: nil as KeyPath<SectionedReminder, String>?) var reminders
    try await $reminders.load()

    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == [""])
  }

  @Test func loadNilSectionBy() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()
    #expect($reminders.sections.sectionNames == ["Home", "Work", "Errands"])

    try await $reminders.load(
      SectionedReminder.order(by: \.id),
      sectionBy: nil as KeyPath<SectionedReminder, String>?
    )
    #expect(reminders.map(\.id) == [1, 2, 3, 4, 5])
    #expect($reminders.sections.sectionNames == [""])

    try await $reminders.load(SectionedReminder.where { $0.id <= 2 }.order(by: \.id))
    #expect(reminders.map(\.title) == ["Dishes", "Standup"])
    #expect($reminders.sections.sectionNames == [""])
  }

  @Test func loadSectionBy() async throws {
    @FetchAll(SectionedReminder.order(by: \.id)) var reminders
    try await $reminders.load()
    #expect($reminders.sections.sectionNames == [""])

    try await $reminders.load(SectionedReminder.order(by: \.id), sectionBy: \.category)
    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == ["Home", "Work", "Errands"])

    try await $reminders.load(SectionedReminder.order(by: \.id), sectionBy: \.priority)
    #expect($reminders.sections.sectionNames == ["high", "low", ""])

    try await $reminders.load(SectionedReminder.where { $0.id <= 2 }.order(by: \.id))
    #expect(reminders.map(\.title) == ["Dishes", "Standup"])
    #expect($reminders.sections.sectionNames == ["high"])
  }

  @Test func equatable() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var byCategory
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var byCategoryToo
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.priority) var byPriority
    @FetchAll(SectionedReminder.order(by: \.id)) var flat
    try await $byCategory.load()
    try await $byCategoryToo.load()
    try await $byPriority.load()
    try await $flat.load()

    #expect(byCategory == byCategoryToo)
    #expect($byCategory == $byCategoryToo)
    #expect($byCategory != $byPriority)
    #expect($byCategory != $flat)
  }

  @Test func sectionsAccessWithoutSectionBy() async throws {
    @FetchAll var reminders: [SectionedReminder]
    try await $reminders.load()

    #expect(!reminders.isEmpty)
    #expect($reminders.sections.count == 1)
    #expect($reminders.sections.sectionNames == [""])
    #expect($reminders.sections[sectionName: ""]?.map(\.id) == reminders.map(\.id))
  }

  @Test func sectionsAccessWithoutSectionByEmptyResults() async throws {
    @FetchAll(SectionedReminder.where { $0.id > 100 }) var reminders
    try await $reminders.load()

    #expect(reminders.isEmpty)
    #expect($reminders.sections.isEmpty)
  }
}

@Table
private struct SectionedReminder: Equatable, Identifiable {
  let id: Int
  var title = ""
  var category = ""
  var priority: String?
}

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "sectionedReminders" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL DEFAULT '',
          "category" TEXT NOT NULL DEFAULT '',
          "priority" TEXT
        )
        """
      )
      .execute(db)
      try SectionedReminder.insert {
        SectionedReminder.Draft(title: "Dishes", category: "Home", priority: "high")
        SectionedReminder.Draft(title: "Standup", category: "Work", priority: "high")
        SectionedReminder.Draft(title: "Groceries", category: "Errands", priority: "low")
        SectionedReminder.Draft(title: "Laundry", category: "Home", priority: nil)
        SectionedReminder.Draft(title: "Review", category: "Work", priority: nil)
      }
      .execute(db)
    }
    return database
  }
}

