import Foundation

@MainActor
final class PRSelectionState: ObservableObject {
    @Published var selectedPRID: String?

    func select(_ pr: PullRequest?) {
        selectedPRID = pr?.stableID
    }
}
