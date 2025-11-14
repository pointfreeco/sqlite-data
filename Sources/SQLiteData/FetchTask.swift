import Sharing

/// A task associated with `@FetchAll`, `@FetchOne`, and `@Fetch` observation.
///
/// This value can be useful in associating the lifetime of observing a query to the lifetime of a
/// SwiftUI view _via_ the `task` view modifier. For example, loading a query in a view's `task`
/// will automatically cancel the observation when drilling down into a child view, and restart
/// observation when popping back to the view:
///
/// ```swift
/// .task {
///   try? await $reminders.load(Reminder.all).task
/// }
/// ```
public struct FetchTask<Value>: Sendable {
  let sharedReader: SharedReader<Value>
  
  /// An async handle to the given fetch observation.
  ///
  /// This handle will suspend until the current task is cancelled, at which point it will terminate
  /// the observation of the associated ``FetchAll``, ``FetchOne``, or ``Fetch``.
  public var task: Void {
    get async throws {
      try await withTaskCancellationHandler {
        try await Task.never()
      } onCancel: {
        cancel()
      }
    }
  }

  /// Cancels the database observation of the associated ``FetchAll``, ``FetchOne``, or ``Fetch``.
  public func cancel() {
    sharedReader.projectedValue = SharedReader(value: sharedReader.wrappedValue)
  }
}
