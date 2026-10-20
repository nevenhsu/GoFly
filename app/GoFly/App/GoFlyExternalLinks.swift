import UIKit

@MainActor
enum GoFlyExternalLinks {
    static func openLocalDevVPN(completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.open(URL(string: "localdevvpn://")!, options: [:]) { accepted in
            Task { @MainActor in
                if accepted { completion(true) } else { openStore(completion: completion) }
            }
        }
    }

    static func openStore(completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.open(URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!, options: [:]) { accepted in
            Task { @MainActor in completion(accepted) }
        }
    }
}
