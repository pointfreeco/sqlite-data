import GRDB
import OrderedCollections

/// A collection of query results grouped into sections.
///
/// You do not create this collection directly. Instead, initialize a ``FetchAll`` property with a
/// `sectionBy:` expression and access this collection from the projected value's
/// ``FetchAll/sections`` property:
///
/// ```swift
/// @FetchAll(Reminder.order(by: \.title), sectionBy: \.category)
/// var reminders
///
/// var body: some View {
///   List {
///     ForEach($reminders.sections) { section in
///       Section(section.name) {
///         ForEach(section) { reminder in
///           Text(reminder.title)
///         }
///       }
///     }
///   }
/// }
/// ```
///
/// Results are grouped into a section for each distinct value of the expression, which is
/// evaluated by the database. Sections are ordered by the expression, ascending, and elements
/// within a section follow the query's order.
public struct ResultsSectionCollection<Element, SectionName: Hashable> {
  let elements: [Element]
  private let elementIndicesBySectionName: OrderedDictionary<SectionName, [Int]>

  init() {
    elements = []
    elementIndicesBySectionName = [:]
  }

  init(elements: [Element], sectionName: SectionName) {
    self.elements = elements
    self.elementIndicesBySectionName =
      elements.isEmpty ? [:] : [sectionName: Array(elements.indices)]
  }

  /// The names of each section in the collection, in the order the sections appear.
  public var sectionNames: [SectionName] {
    Array(elementIndicesBySectionName.keys)
  }

  /// Returns the section with the given name, or `nil` if no such section exists.
  ///
  /// - Parameter name: The name of a section.
  public subscript(sectionName name: SectionName) -> ResultsSection<Element, SectionName>? {
    elementIndicesBySectionName[name].map {
      ResultsSection(name: name, base: elements, elementIndices: $0)
    }
  }

  /// Returns whether or not the collection contains a section with the given name.
  ///
  /// - Parameter name: The name of a section.
  public func contains(sectionName name: SectionName) -> Bool {
    elementIndicesBySectionName.keys.contains(name)
  }

  /// Returns the position of the section with the given name, or `nil` if no such section exists.
  ///
  /// - Parameter name: The name of a section.
  public func index(ofSectionNamed name: SectionName) -> Int? {
    elementIndicesBySectionName.index(forKey: name)
  }
}

extension ResultsSectionCollection where SectionName == String {
  init(cursor: QueryCursor<(Element, String?)>) throws {
    var elements: [Element] = []
    var elementIndicesBySectionName: OrderedDictionary<String, [Int]> = [:]
    while let (element, sectionName) = try cursor.next() {
      elementIndicesBySectionName[sectionName ?? "", default: []].append(elements.count)
      elements.append(element)
    }
    self.elements = elements
    self.elementIndicesBySectionName = elementIndicesBySectionName
  }
}

extension ResultsSectionCollection: RandomAccessCollection {
  public var startIndex: Int {
    elementIndicesBySectionName.elements.startIndex
  }

  public var endIndex: Int {
    elementIndicesBySectionName.elements.endIndex
  }

  public subscript(position: Int) -> ResultsSection<Element, SectionName> {
    let (name, elementIndices) = elementIndicesBySectionName.elements[position]
    return ResultsSection(name: name, base: elements, elementIndices: elementIndices)
  }
}

extension ResultsSectionCollection: Sendable where Element: Sendable, SectionName: Sendable {}

extension ResultsSectionCollection: Equatable where Element: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.elementsEqual(rhs)
  }
}

/// A collection of query results in a section, identified by the section's name.
///
/// See ``ResultsSectionCollection`` for more information.
public struct ResultsSection<Element, SectionName: Hashable>: Identifiable {
  /// The name of the section.
  ///
  /// This is the value of the `sectionBy:` expression shared by every element in the section.
  public let name: SectionName

  private let base: [Element]
  private let elementIndices: [Int]

  init(name: SectionName, base: [Element], elementIndices: [Int]) {
    self.name = name
    self.base = base
    self.elementIndices = elementIndices
  }

  /// The identity of the section, equivalent to its ``name``.
  public var id: SectionName {
    name
  }
}

extension ResultsSection: RandomAccessCollection {
  public var startIndex: Int {
    elementIndices.startIndex
  }

  public var endIndex: Int {
    elementIndices.endIndex
  }

  public subscript(position: Int) -> Element {
    base[elementIndices[position]]
  }
}

extension ResultsSection: Sendable where Element: Sendable, SectionName: Sendable {}

extension ResultsSection: Equatable where Element: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name && lhs.elementsEqual(rhs)
  }
}
