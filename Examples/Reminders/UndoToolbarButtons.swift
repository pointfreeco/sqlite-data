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
    perform(.undo, to: group)
  }

  private func performRedo(to group: UndoGroup? = nil) {
    perform(.redo, to: group)
  }

  private func perform(_ action: UndoAction, to targetGroup: UndoGroup?) {
    guard let undoManager else { return }
    Task {
      await withErrorReporting {
        let stack: [UndoGroup]
        switch action {
        case .undo: stack = undoManager.undoStack
        case .redo: stack = undoManager.redoStack
        }
        let count =
          targetGroup
          .flatMap { target in stack.firstIndex { $0.id == target.id }.map { $0 + 1 } }
          ?? 1
        guard count > 0 else { return }
        for _ in 0..<count {
          let beforeID: UndoGroup.ID?
          switch action {
          case .undo: beforeID = undoManager.undoStack.first?.id
          case .redo: beforeID = undoManager.redoStack.first?.id
          }
          switch action {
          case .undo:
            try await undoManager.undo()
          case .redo:
            try await undoManager.redo()
          }
          let afterID: UndoGroup.ID?
          switch action {
          case .undo: afterID = undoManager.undoStack.first?.id
          case .redo: afterID = undoManager.redoStack.first?.id
          }
          if beforeID == afterID {
            break
          }
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
