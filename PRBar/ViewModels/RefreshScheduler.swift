import Foundation

@MainActor
final class RefreshScheduler {
    typealias RefreshAction = @MainActor () async -> Void

    private var actions: [String: RefreshAction] = [:]
    private var task: Task<Void, Never>?
    private var inFlight = false
    private var pending = false

    func register(key: String, action: @escaping RefreshAction) {
        actions[key] = action
    }

    func unregister(key: String) {
        actions.removeValue(forKey: key)
    }

    func configure(interval: TimeInterval, enabled: Bool) {
        task?.cancel()
        guard enabled else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self?.requestRefresh()
            }
        }
    }

    func requestRefresh() async {
        if inFlight {
            pending = true
            return
        }
        inFlight = true
        defer {
            inFlight = false
        }

        for action in actions.values {
            await action()
        }

        if pending {
            pending = false
            await requestRefresh()
        }
    }
}
