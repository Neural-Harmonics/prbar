import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    @Published var pinnedPRIDs: [String]
    @Published var autoRefreshPaused: Bool

    private let pinnedKey = "monitor.pinned.ids"
    private let pausedKey = "monitor.paused"

    init(defaults: UserDefaults = .standard) {
        pinnedPRIDs = defaults.stringArray(forKey: pinnedKey) ?? []
        autoRefreshPaused = defaults.bool(forKey: pausedKey)
    }

    func pin(_ prID: String) {
        guard !pinnedPRIDs.contains(prID) else { return }
        pinnedPRIDs.append(prID)
        persist()
    }

    func remove(_ prID: String) {
        pinnedPRIDs.removeAll { $0 == prID }
        persist()
    }

    func setPaused(_ paused: Bool) {
        autoRefreshPaused = paused
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(pinnedPRIDs, forKey: pinnedKey)
        UserDefaults.standard.set(autoRefreshPaused, forKey: pausedKey)
    }
}
