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

    #expect(reminders.map(\.id) == [3, 1, 4, 2, 5])
    #expect($reminders.sections.count == 3)
    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])
    #expect($reminders.sections.map(\.name) == ["Errands", "Home", "Work"])
    #expect($reminders.sections[0].map(\.title) == ["Groceries"])
    #expect($reminders.sections[1].map(\.title) == ["Dishes", "Laundry"])
    #expect($reminders.sections[2].map(\.title) == ["Standup", "Review"])
  }

  @Test func queryOrderAppliesWithinSections() async throws {
    @FetchAll(SectionedReminder.order { $0.title.desc() }, sectionBy: \.category)
    var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])
    #expect($reminders.sections[1].map(\.title) == ["Laundry", "Dishes"])
    #expect($reminders.sections[2].map(\.title) == ["Standup", "Review"])
  }

  @Test func optionalSectionName() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.priority) var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == [nil, "high", "low"])
    #expect($reminders.sections[sectionName: nil]?.map(\.title) == ["Laundry", "Review"])
  }

  @Test func expressionSectionName() async throws {
    @FetchAll(
      SectionedReminder.order(by: \.id),
      sectionBy: { Case().when($0.id <= 2, then: "First").else("Rest") }
    )
    var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == ["First", "Rest"])
    #expect($reminders.sections[sectionName: "First"]?.map(\.id) == [1, 2])
    #expect($reminders.sections[sectionName: "Rest"]?.map(\.id) == [3, 4, 5])
  }

  @Test func descendingSections() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: { $0.category.desc() }) var reminders
    try await $reminders.load()

    #expect(reminders.map(\.id) == [2, 5, 1, 4, 3])
    #expect($reminders.sections.sectionNames == ["Work", "Home", "Errands"])
    #expect($reminders.sections[0].map(\.title) == ["Standup", "Review"])

    try await $reminders.load(
      SectionedReminder.order(by: \.id),
      sectionBy: { $0.priority.desc(nulls: .last) }
    )
    #expect($reminders.sections.sectionNames == ["low", "high", nil])
    #expect($reminders.sections[sectionName: nil]?.map(\.title) == ["Laundry", "Review"])
  }

  @Test func emptySectionNameSortsWithNullSectionName() async throws {
    try await database.write { db in
      try SectionedReminder.insert {
        SectionedReminder.Draft(title: "Errand", category: "Errands", priority: "")
      }
      .execute(db)
    }

    @FetchAll(
      SectionedReminder.order(by: \.id),
      sectionBy: { $0.priority.asc(nulls: .last) }
    )
    var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == ["", "high", "low", nil])
    #expect($reminders.sections[sectionName: ""]?.map(\.title) == ["Errand"])
    #expect($reminders.sections[sectionName: nil]?.map(\.title) == ["Laundry", "Review"])
  }

  @Test func discontiguousSection() async throws {
    try await database.write { db in
      try #sql(
        """
        CREATE TABLE "sectionedValues" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL DEFAULT '',
          "value"
        )
        """
      )
      .execute(db)
      try #sql(
        """
        INSERT INTO "sectionedValues" ("title", "value")
        VALUES ('first', 5), ('second', 10), ('third', '5')
        """
      )
      .execute(db)
    }

    @FetchAll(SectionedValue.order(by: \.id), sectionBy: \.value) var values
    try await $values.load()

    #expect($values.sections.sectionNames == ["5", "10"])
    #expect($values.sections[sectionName: "5"]?.map(\.title) == ["first", "third"])
    #expect($values.sections[sectionName: "10"]?.map(\.title) == ["second"])
    #expect($values.sections.map { $0.map(\.title) } == [["first", "third"], ["second"]])
  }

  @Test(arguments: [true, false]) func dynamicSectionBy(isSectioned: Bool) async throws {
    @FetchAll(
      SectionedReminder.order(by: \.id),
      sectionBy: {
        if isSectioned {
          $0.category
        }
      }
    )
    var reminders
    try await $reminders.load()

    #expect(reminders.count == 5)
    #expect(
      $reminders.sections.sectionNames == (isSectioned ? ["Errands", "Home", "Work"] : [nil])
    )
  }

  @Test(arguments: [true, false]) func ifElseSectionBy(byCategory: Bool) async throws {
    @FetchAll(
      SectionedReminder.order(by: \.id),
      sectionBy: {
        if byCategory {
          $0.category
        } else {
          $0.priority.desc(nulls: .last)
        }
      }
    )
    var reminders
    try await $reminders.load()

    #expect(
      $reminders.sections.sectionNames
        == (byCategory ? ["Errands", "Home", "Work"] : ["low", "high", nil])
    )
  }

  @Test func keyPathSectionBy() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])

    try await $reminders.load(SectionedReminder.order(by: \.id), sectionBy: \.priority)
    #expect($reminders.sections.sectionNames == [nil, "high", "low"])
  }

  @Test func keyPathSectionByWholeTable() async throws {
    @FetchAll(sectionBy: \.category) var reminders: [SectionedReminder]
    try await $reminders.load()

    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])
  }

  @Test func storedSectioning() async throws {
    let sectioning: (SectionedReminder.TableColumns) -> _Sectioning? = { _Sectioning($0.category) }
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: sectioning) var reminders
    try await $reminders.load()

    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])
  }

  @Test func sectionLookup() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()

    let sections = $reminders.sections
    #expect(sections[sectionName: "Work"]?.map(\.title) == ["Standup", "Review"])
    #expect(sections[sectionName: "Gym"] == nil)
    #expect(sections.contains(sectionName: "Errands"))
    #expect(!sections.contains(sectionName: "Gym"))
    #expect(sections.index(ofSectionNamed: "Home") == 1)
    #expect(sections.index(ofSectionNamed: "Errands") == 0)
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
    #expect($reminders.sections.sectionNames == ["Errands", "Gym", "Home", "Work"])
    #expect($reminders.sections[sectionName: "Gym"]?.map(\.title) == ["Squats"])
  }

  @Test func loadStatementRemovesSectioning() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()
    #expect($reminders.sections.count == 3)

    try await $reminders.load(SectionedReminder.where { $0.category.neq("Work") }.order(by: \.id))

    #expect(reminders.map(\.title) == ["Dishes", "Groceries", "Laundry"])
    #expect($reminders.sections.sectionNames == [nil])
    #expect($reminders.sections[0].map(\.title) == ["Dishes", "Groceries", "Laundry"])
  }

  @Test func emptyResults() async throws {
    @FetchAll(SectionedReminder.where { $0.id > 100 }, sectionBy: \.category) var reminders
    try await $reminders.load()

    #expect(reminders.isEmpty)
    #expect($reminders.sections.isEmpty)
    #expect($reminders.sections.sectionNames.isEmpty)
  }

  @Test func defaultWrappedValue() throws {
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
    #expect($reminders.sections.sectionNames == [nil])
    #expect($reminders.sections[0].map(\.title) == ["A", "B", "C"])
  }

  @Test func wholeTable() async throws {
    @FetchAll(sectionBy: \.category) var reminders: [SectionedReminder]
    try await $reminders.load()

    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])
  }

  @Test func reassignment() async throws {
    @FetchAll(SectionedReminder.order(by: \.id)) var reminders
    try await $reminders.load()
    #expect(reminders.count == 5)

    $reminders = FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category)
    try await $reminders.load()
    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])

    $reminders = FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.priority)
    try await $reminders.load()
    #expect($reminders.sections.sectionNames == [nil, "high", "low"])

    $reminders = FetchAll(SectionedReminder.order(by: \.title))
    try await $reminders.load()
    #expect(reminders.map(\.title) == ["Dishes", "Groceries", "Laundry", "Review", "Standup"])
    #expect($reminders.sections.sectionNames == [nil])
    #expect($reminders.sections[0].count == 5)
  }

  @Test func nilSectionBy() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: { _ in nil }) var reminders
    try await $reminders.load()

    #expect(reminders.map(\.id) == [1, 2, 3, 4, 5])
    #expect($reminders.sections.sectionNames == [nil])
    #expect($reminders.sections[0].map(\.id) == [1, 2, 3, 4, 5])
  }

  @Test func nilSectionBy2() async throws {
    let isSectioned = false
    @FetchAll(
      SectionedReminder.order(by: \.id),
      sectionBy: {
        if isSectioned {
          $0.title
        }
      }
    ) var reminders
    try await $reminders.load()

    #expect(reminders.map(\.id) == [1, 2, 3, 4, 5])
    #expect($reminders.sections.sectionNames == [nil])
    #expect($reminders.sections[0].map(\.id) == [1, 2, 3, 4, 5])
  }

  @Test func nilSectionByWholeTable() async throws {
    @FetchAll(sectionBy: { _ in nil }) var reminders: [SectionedReminder]
    try await $reminders.load()

    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == [nil])
  }

  @Test func loadNilSectionBy() async throws {
    @FetchAll(SectionedReminder.order(by: \.id), sectionBy: \.category) var reminders
    try await $reminders.load()
    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])

    try await $reminders.load(SectionedReminder.order(by: \.id), sectionBy: { _ in nil })
    #expect(reminders.map(\.id) == [1, 2, 3, 4, 5])
    #expect($reminders.sections.sectionNames == [nil])

    try await $reminders.load(SectionedReminder.where { $0.id <= 2 }.order(by: \.id))
    #expect(reminders.map(\.title) == ["Dishes", "Standup"])
    #expect($reminders.sections.sectionNames == [nil])
  }

  @Test func loadSectionBy() async throws {
    @FetchAll(SectionedReminder.order(by: \.id)) var reminders
    try await $reminders.load()
    #expect($reminders.sections.sectionNames == [nil])

    try await $reminders.load(SectionedReminder.order(by: \.id), sectionBy: \.category)
    #expect(reminders.count == 5)
    #expect($reminders.sections.sectionNames == ["Errands", "Home", "Work"])

    try await $reminders.load(SectionedReminder.order(by: \.id), sectionBy: \.priority)
    #expect($reminders.sections.sectionNames == [nil, "high", "low"])

    try await $reminders.load(SectionedReminder.where { $0.id <= 2 }.order(by: \.id))
    #expect(reminders.map(\.title) == ["Dishes", "Standup"])
    #expect($reminders.sections.sectionNames == [nil])
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

  @Test func selectionSectionBy() async throws {
    let statement =
      SectionedReminder
      .order(by: \.id)
      .select { SectionedRow.Columns(title: $0.title, label: $0.category) }
    @FetchAll(statement, sectionBy: { $0.category }) var rows
    try await $rows.load()

    #expect(rows.map(\.title) == ["Groceries", "Dishes", "Laundry", "Standup", "Review"])
    #expect($rows.sections.sectionNames == ["Errands", "Home", "Work"])
    #expect($rows.sections[sectionName: "Home"]?.map(\.title) == ["Dishes", "Laundry"])
  }

  @Test func joinedSectionBy() async throws {
    let statement =
      SectionedReminder
      .order(by: \.id)
      .join(SectionedCategory.all) { $0.category.eq($1.name) }
      .select { SectionedRow.Columns(title: $0.title, label: $1.label) }
    @FetchAll(statement, sectionBy: { $1.label }) var rows
    try await $rows.load()

    #expect(rows.map(\.title) == ["Dishes", "Laundry", "Standup", "Review", "Groceries"])
    #expect($rows.sections.sectionNames == ["At Home", "At Work", "Out & About"])
    #expect($rows.sections[sectionName: "At Home"]?.map(\.title) == ["Dishes", "Laundry"])
    #expect($rows.sections[sectionName: "Out & About"]?.map(\.title) == ["Groceries"])
  }

  @Test func joinedDescendingSectionBy() async throws {
    let statement =
      SectionedReminder
      .order(by: \.id)
      .join(SectionedCategory.all) { $0.category.eq($1.name) }
      .select { SectionedRow.Columns(title: $0.title, label: $1.label) }
    @FetchAll(statement, sectionBy: { $1.label.desc() }) var rows
    try await $rows.load()

    #expect($rows.sections.sectionNames == ["Out & About", "At Work", "At Home"])
  }

  @Test func loadJoinedSectionBy() async throws {
    let statement =
      SectionedReminder
      .order(by: \.id)
      .join(SectionedCategory.all) { $0.category.eq($1.name) }
      .select { SectionedRow.Columns(title: $0.title, label: $1.label) }
    @FetchAll(statement) var rows
    try await $rows.load()
    #expect($rows.sections.sectionNames == [nil])

    try await $rows.load(statement, sectionBy: { $1.label })
    #expect(rows.map(\.title) == ["Dishes", "Laundry", "Standup", "Review", "Groceries"])
    #expect($rows.sections.sectionNames == ["At Home", "At Work", "Out & About"])
  }

  @Test(arguments: [true, false]) func dynamicJoinedSectionBy(isSectioned: Bool) async throws {
    let statement =
      SectionedReminder
      .order(by: \.id)
      .join(SectionedCategory.all) { $0.category.eq($1.name) }
      .select { SectionedRow.Columns(title: $0.title, label: $1.label) }
    @FetchAll(
      statement,
      sectionBy: {
        if isSectioned {
          $1.label
        }
      }
    )
    var rows
    try await $rows.load()

    #expect(rows.count == 5)
    #expect(
      $rows.sections.sectionNames
        == (isSectioned ? ["At Home", "At Work", "Out & About"] : [nil])
    )
  }

  @Test func twoJoinsSectionBy() async throws {
    let statement =
      SectionedReminder
      .order(by: \.id)
      .join(SectionedCategory.all) { $0.category.eq($1.name) }
      .join(SectionedPriority.all) { reminder, _, priority in reminder.priority.eq(priority.name) }
      .select { SectionedRow.Columns(title: $0.title, label: $2.label) }
    @FetchAll(statement, sectionBy: { $2.label }) var rows
    try await $rows.load()

    #expect(rows.map(\.title) == ["Dishes", "Standup", "Groceries"])
    #expect($rows.sections.sectionNames == ["High!", "Low!"])
    #expect($rows.sections[sectionName: "High!"]?.map(\.title) == ["Dishes", "Standup"])
    #expect($rows.sections[sectionName: "Low!"]?.map(\.title) == ["Groceries"])
  }

  @Test func threeJoinsSectionBy() async throws {
    let statement =
      SectionedReminder
      .order(by: \.id)
      .join(SectionedCategory.all) { $0.category.eq($1.name) }
      .join(SectionedPriority.all) { reminder, _, priority in reminder.priority.eq(priority.name) }
      .join(SectionedUrgency.all) { reminder, _, _, urgency in
        reminder.priority.eq(urgency.name)
      }
      .select { SectionedRow.Columns(title: $0.title, label: $3.label) }
    @FetchAll(statement, sectionBy: { $3.label }) var rows
    try await $rows.load()

    #expect(rows.map(\.title) == ["Groceries", "Dishes", "Standup"])
    #expect($rows.sections.sectionNames == ["Later", "Now"])
    #expect($rows.sections[sectionName: "Now"]?.map(\.title) == ["Dishes", "Standup"])
    #expect($rows.sections[sectionName: "Later"]?.map(\.title) == ["Groceries"])
  }

  @Test func sectionsAccessWithoutSectionBy() async throws {
    @FetchAll var reminders: [SectionedReminder]
    try await $reminders.load()

    #expect(!reminders.isEmpty)
    #expect($reminders.sections.count == 1)
    #expect($reminders.sections.sectionNames == [nil])
    #expect($reminders.sections[sectionName: nil]?.map(\.id) == reminders.map(\.id))
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

@Selection
private struct SectionedRow: Equatable {
  var title = ""
  var label = ""
}

@Table
private struct SectionedValue: Equatable, Identifiable {
  let id: Int
  var title = ""
  var value: String?
}

@Table
private struct SectionedCategory: Equatable, Identifiable {
  let id: Int
  var name = ""
  var label = ""
}

@Table
private struct SectionedPriority: Equatable, Identifiable {
  let id: Int
  var name = ""
  var label = ""
}

@Table
private struct SectionedUrgency: Equatable, Identifiable {
  let id: Int
  var name = ""
  var label = ""
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
      try #sql(
        """
        CREATE TABLE "sectionedCategories" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "name" TEXT NOT NULL DEFAULT '',
          "label" TEXT NOT NULL DEFAULT ''
        )
        """
      )
      .execute(db)
      try SectionedCategory.insert {
        SectionedCategory.Draft(name: "Home", label: "At Home")
        SectionedCategory.Draft(name: "Work", label: "At Work")
        SectionedCategory.Draft(name: "Errands", label: "Out & About")
      }
      .execute(db)
      try #sql(
        """
        CREATE TABLE "sectionedPriorities" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "name" TEXT NOT NULL DEFAULT '',
          "label" TEXT NOT NULL DEFAULT ''
        )
        """
      )
      .execute(db)
      try SectionedPriority.insert {
        SectionedPriority.Draft(name: "high", label: "High!")
        SectionedPriority.Draft(name: "low", label: "Low!")
      }
      .execute(db)
      try #sql(
        """
        CREATE TABLE "sectionedUrgencies" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "name" TEXT NOT NULL DEFAULT '',
          "label" TEXT NOT NULL DEFAULT ''
        )
        """
      )
      .execute(db)
      try SectionedUrgency.insert {
        SectionedUrgency.Draft(name: "high", label: "Now")
        SectionedUrgency.Draft(name: "low", label: "Later")
      }
      .execute(db)
    }
    return database
  }
}
