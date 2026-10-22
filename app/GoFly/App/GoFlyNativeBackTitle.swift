import SwiftUI
import UIKit

extension View {
    func goFlyNativeBackTitle(_ key: String? = nil) -> some View {
        background(GoFlyNativeBackTitle(title: key.map(goFlyString) ?? "").frame(width: 0, height: 0))
    }
}

/// Set the hosting navigation item's title while keeping UIKit's native back action and edge gesture.
private struct GoFlyNativeBackTitle: UIViewControllerRepresentable {
    let title: String

    func makeUIViewController(context: Context) -> Controller { Controller(title: title) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.backTitle = title
        controller.applyTitle()
    }

    final class Controller: UIViewController {
        var backTitle: String

        init(title: String) {
            backTitle = title
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyTitle()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyTitle()
        }

        func applyTitle() {
            var ancestor = parent
            while let controller = ancestor {
                if let navigation = controller.navigationController,
                   navigation.viewControllers.contains(where: { $0 === controller }) {
                    if backTitle.isEmpty {
                        controller.navigationItem.backButtonTitle = ""
                        controller.navigationItem.backButtonDisplayMode = .minimal
                    } else {
                        controller.navigationItem.backButtonTitle = backTitle
                        controller.navigationItem.backButtonDisplayMode = .default
                    }
                    return
                }
                ancestor = controller.parent
            }
        }
    }
}
