import AppKit

@MainActor
final class ClipboardMonitor {
    struct Snapshot {
        let timestamp: Date
        let changeCount: Int
        let itemCount: Int
        let typeCounts: [String: Int]
        let items: [NSPasteboardItem]
        let sourceAppName: String?
        let sourceAppBundleId: String?
    }

    private let pasteboard: NSPasteboard
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int
    private let onChange: (Snapshot) -> Void
    private var pendingSnapshot: Snapshot?
    private var pendingWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 0.2

    init(
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 0.5,
        onChange: @escaping (Snapshot) -> Void
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
        self.onChange = onChange
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChange()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChange() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let items = pasteboard.pasteboardItems ?? []
        var typeCounts: [String: Int] = [:]
        for item in items {
            for type in item.types {
                typeCounts[type.rawValue, default: 0] += 1
            }
        }

        let frontmost = NSWorkspace.shared.frontmostApplication

        let snapshot = Snapshot(
            timestamp: Date(),
            changeCount: changeCount,
            itemCount: items.count,
            typeCounts: typeCounts,
            items: items,
            sourceAppName: frontmost?.localizedName,
            sourceAppBundleId: frontmost?.bundleIdentifier
        )
        pendingSnapshot = snapshot
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pendingSnapshot else { return }
            self.onChange(pending)
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }
}
