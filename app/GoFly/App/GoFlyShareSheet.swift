import SwiftUI
import UIKit

struct DiagnosticsShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// System share sheet for the exported diagnostics file.
struct GoFlyShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
