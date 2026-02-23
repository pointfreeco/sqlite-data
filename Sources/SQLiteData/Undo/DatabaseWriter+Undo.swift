import Foundation
#if canImport(SwiftUI)
  import SwiftUI
#endif

public extension DatabaseWriter {
  #if canImport(SwiftUI)
    @available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
    func writeWithUndoGroup<T>(
      _ description: LocalizedStringKey,
      _ updates: (Database) throws -> T
    ) throws -> T {
      @Dependency(\.defaultUndoManager) var defaultUndoManager
      let undoManager =
        (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
        ?? UndoManager.manager(for: self)
      if let undoManager {
        return try undoManager.withGroup(description, updates)
      }
      return try write(updates)
    }
  #endif

  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  @_disfavoredOverload
  func writeWithUndoGroup<T>(
    _ description: LocalizedStringResource,
    _ updates: (Database) throws -> T
  ) throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager =
      (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
      ?? UndoManager.manager(for: self)
    if let undoManager {
      return try undoManager.withGroup(description, updates)
    }
    return try write(updates)
  }

  @_disfavoredOverload
  func writeWithUndoGroup<T>(
    _ description: String,
    _ updates: (Database) throws -> T
  ) throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager =
      (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
      ?? UndoManager.manager(for: self)
    if let undoManager {
      return try undoManager.withGroup(description, updates)
    }
    return try write(updates)
  }

  #if canImport(SwiftUI)
    @available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
    @_disfavoredOverload
    func writeWithUndoGroup<T: Sendable>(
      _ description: LocalizedStringKey,
      _ updates: @Sendable (Database) throws -> T
    ) async throws -> T {
      @Dependency(\.defaultUndoManager) var defaultUndoManager
      let undoManager =
        (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
        ?? UndoManager.manager(for: self)
      if let undoManager {
        return try await undoManager.withGroup(description, updates)
      }
      return try await write(updates)
    }
  #endif

  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  func writeWithUndoGroup<T: Sendable>(
    _ description: LocalizedStringResource,
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager =
      (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
      ?? UndoManager.manager(for: self)
    if let undoManager {
      return try await undoManager.withGroup(description, updates)
    }
    return try await write(updates)
  }

  @_disfavoredOverload
  func writeWithUndoGroup<T: Sendable>(
    _ description: String,
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager =
      (defaultUndoManager?.manages(database: self) == true ? defaultUndoManager : nil)
      ?? UndoManager.manager(for: self)
    if let undoManager {
      return try await undoManager.withGroup(description, updates)
    }
    return try await write(updates)
  }
}
