import Cocoa
import Carbon

@MainActor
final class PasteyApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var toggleMenuItem: NSMenuItem?
    private var clipboardMonitor: ClipboardMonitor?
    private let settings = SettingsStore()
    private var store: ClipboardHistoryStore?
    private let normalizer = ClipboardNormalizer()
    private let classifier = ClipboardClassifier()
    private var windowController: ClipboardWindowController?
    private var hotkeyManager: HotkeyManager?
    private var preferencesController: PreferencesWindowController?
    private var localAPIServer: LocalAPIServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipboardHistoryStore(retentionLimit: settings.retentionLimit, persistence: ClipboardPersistence())
        setupStatusItem()
        setupWindowController()
        startClipboardMonitor()
        registerHotkey()
        showWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsChange), name: .settingsDidChange, object: settings)
        configureLocalAPI()
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            toggleWindow()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusMenu()
        } else {
            toggleWindow()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastey")
            if let image {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                button.imagePosition = .imageLeft
            } else {
                button.title = "Pastey"
            }
            if button.title.isEmpty {
                button.title = "Pastey"
            }
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.toolTip = "Pastey"
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem?.isVisible = true
        configureStatusMenu()
    }

    private func setupWindowController() {
        guard let store else { return }
        windowController = ClipboardWindowController(store: store)
        localAPIServer = LocalAPIServer(store: store)
    }

    private func startClipboardMonitor() {
        clipboardMonitor = ClipboardMonitor { [weak self] snapshot in
            guard let self else { return }
            if self.settings.isIgnored(bundleId: snapshot.sourceAppBundleId) {
                return
            }
            let normalized = self.normalizer.normalize(
                items: snapshot.items,
                capturedAt: snapshot.timestamp,
                sourceAppName: snapshot.sourceAppName,
                sourceAppBundleId: snapshot.sourceAppBundleId
            )
            let entries = normalized.map { content in
                ClipboardEntry(item: self.classifier.classify(content), content: content)
            }
            self.store?.add(entries)
        }
        clipboardMonitor?.start()
    }

    private func registerHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.toggleWindow()
            }
        }
        hotkeyManager?.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
    }

    private func toggleWindow() {
        guard let window = windowController?.window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)
        windowController?.focusSearch()
    }

    private func configureStatusMenu() {
        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        statusMenu.addItem(preferencesItem)
        statusMenu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Open Pastey", action: #selector(toggleWindowFromMenu), keyEquivalent: "")
        toggleItem.target = self
        toggleMenuItem = toggleItem
        statusMenu.addItem(toggleItem)
        statusMenu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "Restart Pastey", action: #selector(restartApp), keyEquivalent: "r")
        restartItem.keyEquivalentModifierMask = [.command]
        restartItem.target = self
        statusMenu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit Pastey", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func toggleWindowFromMenu() {
        toggleWindow()
    }

    private func showStatusMenu() {
        if let window = windowController?.window, let toggleMenuItem {
            toggleMenuItem.title = window.isVisible ? "Hide Pastey" : "Open Pastey"
        }
        guard let event = NSApp.currentEvent, let button = statusItem?.button else { return }
        NSMenu.popUpContextMenu(statusMenu, with: event, for: button)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(settings: settings)
        }
        preferencesController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleSettingsChange() {
        store?.updateRetentionLimit(settings.retentionLimit)
        configureLocalAPI()
    }

    @objc private func restartApp() {
        guard let executable = CommandLine.arguments.first else {
            NSApp.terminate(nil)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try process.run()
        } catch {
            NSApp.terminate(nil)
            return
        }
        NSApp.terminate(nil)
    }

    private func configureLocalAPI() {
        guard let server = localAPIServer else { return }
        if settings.localAPIEnabled {
            server.start(port: settings.localAPIPort)
        } else {
            server.stop()
        }
    }
}

let app = NSApplication.shared
let delegate = PasteyApp()
app.delegate = delegate
let showDockIcon = true
app.setActivationPolicy(showDockIcon ? .regular : .accessory)
app.run()
