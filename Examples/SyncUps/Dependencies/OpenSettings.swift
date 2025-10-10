import Dependencies
import UIKit

extension DependencyValues {
  nonisolated var openSettings: @Sendable () async -> Void {
    get { self[OpenSettingsKey.self] }
    set { self[OpenSettingsKey.self] = newValue }
  }

  nonisolated private enum OpenSettingsKey: DependencyKey {
    typealias Value = @Sendable () async -> Void

    static let liveValue: @Sendable () async -> Void = {
      await MainActor.run {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
      }
    }
  }
}
