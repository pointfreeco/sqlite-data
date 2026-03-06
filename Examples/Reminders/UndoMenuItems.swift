import SQLiteData
import SwiftUI

struct UndoMenuItems: View {
  @Dependency(\.defaultUndoManager) private var undoManager

  var body: some View {
    if let undoManager {
      ControlGroup {
        Button {
          performUndo()
        } label: {
          Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(!undoManager.canUndo)
        
        Button {
          performRedo()
        } label: {
          Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(!undoManager.canRedo)
        
      }
      .controlGroupStyle(.menu)
      
      if !undoManager.undoStack.isEmpty {
        Menu {
          ForEach(undoManager.undoStack) { group in
            Button("Undo \(group.description)") {
              performUndo(to: group)
            }
          }
        } label: {
          Label("Undo", systemImage: "arrow.uturn.backward.square")
        }
      }
      
      if !undoManager.redoStack.isEmpty {
        Menu {
          ForEach(undoManager.redoStack) { group in
            Button("Redo \(group.description)") {
              performRedo(to: group)
            }
          }
        } label: {
          Label("Redo", systemImage: "arrow.uturn.forward.square")
        }
      }
    }
  }

  private func performUndo(to group: UndoGroup? = nil) {
    guard let undoManager else { return }
    Task {
      await withErrorReporting {
        if let group {
          try await undoManager.undo(to: group)
        } else {
          try await undoManager.undo()
        }
      }
    }
  }

  private func performRedo(to group: UndoGroup? = nil) {
    guard let undoManager else { return }
    Task {
      await withErrorReporting {
        if let group {
          try await undoManager.redo(to: group)
        } else {
          try await undoManager.redo()
        }
      }
    }
  }
}

struct BindSQLiteUndoManagerToSystemUndo: ViewModifier {
  @Dependency(\.defaultUndoManager) private var sqliteUndoManager
  @Environment(\.undoManager) private var foundationUndoManager

  func body(content: Content) -> some View {
    content
      .task(id: foundationUndoManager.map(ObjectIdentifier.init)) {
        sqliteUndoManager?.bind(to: foundationUndoManager)
      }
  }
}

extension View {
  func bindSQLiteUndoManagerToSystemUndo() -> some View {
    modifier(BindSQLiteUndoManagerToSystemUndo())
  }
}
