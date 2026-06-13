import Foundation
#if canImport(SwiftUI)
  import SwiftUI
#endif

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public extension DatabaseWriter {
  #if canImport(SwiftUI)
    func writeWithUndoGroup<T>(
      _ description: LocalizedStringKey,
      _ updates: (Database) throws -> T
    ) throws -> T {
      @Dependency(\.defaultUndoManager) var defaultUndoManager
      let undoManager = UndoManager.manager(for: self, defaultUndoManager: defaultUndoManager)
      if let undoManager {
        return try undoManager.withGroup(description, updates)
      }
      return try write(updates)
    }
  #endif

  @_disfavoredOverload
  func writeWithUndoGroup<T>(
    _ description: LocalizedStringResource,
    _ updates: (Database) throws -> T
  ) throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager = UndoManager.manager(for: self, defaultUndoManager: defaultUndoManager)
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
    let undoManager = UndoManager.manager(for: self, defaultUndoManager: defaultUndoManager)
    if let undoManager {
      return try undoManager.withGroup(description, updates)
    }
    return try write(updates)
  }

  #if canImport(SwiftUI)
    @_disfavoredOverload
    func writeWithUndoGroup<T: Sendable>(
      _ description: LocalizedStringKey,
      _ updates: @Sendable (Database) throws -> T
    ) async throws -> T {
      @Dependency(\.defaultUndoManager) var defaultUndoManager
      let undoManager = UndoManager.manager(for: self, defaultUndoManager: defaultUndoManager)
      if let undoManager {
        return try await undoManager.withGroup(description, updates)
      }
      return try await write(updates)
    }
  #endif

  func writeWithUndoGroup<T: Sendable>(
    _ description: LocalizedStringResource,
    _ updates: @Sendable (Database) throws -> T
  ) async throws -> T {
    @Dependency(\.defaultUndoManager) var defaultUndoManager
    let undoManager = UndoManager.manager(for: self, defaultUndoManager: defaultUndoManager)
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
    let undoManager = UndoManager.manager(for: self, defaultUndoManager: defaultUndoManager)
    if let undoManager {
      return try await undoManager.withGroup(description, updates)
    }
    return try await write(updates)
  }
}
