import AVFoundation
import Dependencies
import DependenciesMacros

@DependencyClient
struct SoundEffectClient {
  var load: @Sendable (_ fileName: String) -> Void
  var play: @Sendable () -> Void
}

extension SoundEffectClient: DependencyKey {
  static var liveValue: Self {
    let player = LockIsolated(AVPlayer())
    return Self(
      load: { fileName in
        player.withValue {
          guard let url = Bundle.main.url(forResource: fileName, withExtension: "")
          else { return }
          $0.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
      },
      play: {
        player.withValue {
          $0.seek(to: .zero)
          $0.play()
        }
      }
    )
  }

  static let testValue = Self()

  static let noop = Self(
    load: { _ in },
    play: {}
  )
}

extension DependencyValues {
  var soundEffectClient: SoundEffectClient {
    get { self[SoundEffectClient.self] }
    set { self[SoundEffectClient.self] = newValue }
  }
}
