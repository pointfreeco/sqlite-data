import AppKit
import SwiftUI

final class DetailViewController: NSViewController {
  init() {
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  override func loadView() {
    let hostingView = FullSizeHostingView(
      rootView: DetailView()
        .frame(
          minWidth: 600,
          maxWidth: .infinity,
          minHeight: 500,
          maxHeight: .infinity
        )
    )
    self.view = hostingView
  }
  class FullSizeHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
      return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
  }
}

struct DetailView: View {
  var body: some View {
    Color.blue
  }
}

#Preview {
  DetailViewController()
}
