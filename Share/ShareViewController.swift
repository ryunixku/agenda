import UIKit

/// Placeholder until the share extension is built (M6), where the shared item becomes a task.
/// For now it closes straight away.
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
