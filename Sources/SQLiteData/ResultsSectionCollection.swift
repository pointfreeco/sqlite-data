import GRDB
import OrderedCollections

/// A collection of query results grouped into sections.
///
/// You do not create this collection directly. Instead, initialize a ``FetchAll`` property with a
/// `sectionBy:` key path and access this collection from the projected value's
/// ``FetchAll/sections`` property:
///
/// ```swift
/// @FetchAll(Reminder.order(by: \.category), sectionBy: \.category)
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
/// Results are grouped into a section for each distinct value at the key path. Sections are
/// ordered by the position of their first element in the query's results, and elements within a
/// section follow the query's order. To control the order of sections, order the query by the
/// sectioned column.
public struct ResultsSectionCollection<Element, SectionName: Hashable> {
  let elements: [Element]
  private let elementIndicesBySectionName: OrderedDictionary<SectionName, [Int]>

  init() {
    elements = []
    elementIndicesBySectionName = [:]
  }

  init(elements: some Sequence<Element>, sectionName: (Element) -> SectionName) {
    var allElements: [Element] = []
    var elementIndicesBySectionName: OrderedDictionary<SectionName, [Int]> = [:]
    for element in elements {
      elementIndicesBySectionName[sectionName(element), default: []].append(allElements.count)
      allElements.append(element)
    }
    self.elements = allElements
    self.elementIndicesBySectionName = elementIndicesBySectionName
  }

  init(elements: [Element], sectionName: SectionName) {
    self.elements = elements
    self.elementIndicesBySectionName =
      elements.isEmpty ? [:] : [sectionName: Array(elements.indices)]
  }

  init(cursor: QueryCursor<Element>, sectionName: (Element) -> SectionName) throws {
    var elements: [Element] = []
    while let element = try cursor.next() {
      elements.append(element)
    }
    self.init(elements: elements, sectionName: sectionName)
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
  /// This is the value at the `sectionBy:` key path shared by every element in the section.
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

struct SectionBy<Element>: Hashable, Sendable {
  let keyPath: AnyHashableSendable
  let name: @Sendable (Element) -> String

  init(_ keyPath: KeyPath<Element, String>) {
    let keyPath = unsafeBitCast(keyPath, to: (any KeyPath<Element, String> & Sendable).self)
    self.keyPath = AnyHashableSendable(keyPath)
    self.name = { $0[keyPath: keyPath] }
  }

  init(_ keyPath: KeyPath<Element, String?>) {
    let keyPath = unsafeBitCast(keyPath, to: (any KeyPath<Element, String?> & Sendable).self)
    self.keyPath = AnyHashableSendable(keyPath)
    self.name = { $0[keyPath: keyPath] ?? "" }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.keyPath == rhs.keyPath
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(keyPath)
  }
}
