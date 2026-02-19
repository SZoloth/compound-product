import Foundation

extension Notification.Name {
    static let settingsDidChange = Notification.Name("pastey.settings.didChange")
}

@MainActor
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let retentionKey = "pastey.retention.limit"
    private let ignoreListKey = "pastey.ignore.list"
    private let localAPIEnabledKey = "pastey.local.api.enabled"
    private let localAPIPortKey = "pastey.local.api.port"

    private(set) var retentionLimit: Int
    private(set) var ignoreList: [String]
    private(set) var localAPIEnabled: Bool
    private(set) var localAPIPort: Int

    init() {
        let storedRetention = defaults.integer(forKey: retentionKey)
        self.retentionLimit = storedRetention > 0 ? storedRetention : 200
        self.ignoreList = defaults.array(forKey: ignoreListKey) as? [String] ?? []
        self.localAPIEnabled = defaults.bool(forKey: localAPIEnabledKey)
        let storedPort = defaults.integer(forKey: localAPIPortKey)
        self.localAPIPort = storedPort > 0 ? storedPort : 8899
    }

    func updateRetentionLimit(_ limit: Int) {
        let clamped = max(10, min(1000, limit))
        retentionLimit = clamped
        defaults.set(clamped, forKey: retentionKey)
        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }

    func updateIgnoreList(_ list: [String]) {
        let normalized = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        ignoreList = normalized
        defaults.set(normalized, forKey: ignoreListKey)
        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }

    func updateLocalAPIEnabled(_ enabled: Bool) {
        localAPIEnabled = enabled
        defaults.set(enabled, forKey: localAPIEnabledKey)
        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }

    func updateLocalAPIPort(_ port: Int) {
        let clamped = max(1024, min(65535, port))
        localAPIPort = clamped
        defaults.set(clamped, forKey: localAPIPortKey)
        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }

    func ignoreListString() -> String {
        ignoreList.joined(separator: "\n")
    }

    func isIgnored(bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return ignoreList.contains(bundleId)
    }
}
