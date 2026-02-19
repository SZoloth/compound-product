import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController, NSTextViewDelegate, NSTextFieldDelegate {
    private let settings: SettingsStore
    private let retentionValueLabel = NSTextField(labelWithString: "")
    private let retentionStepper = NSStepper()
    private let ignoreTextView = NSTextView()
    private let apiToggle = NSButton(checkboxWithTitle: "Enable Local API", target: nil, action: nil)
    private let apiPortField = NSTextField()
    private let apiHintLabel = NSTextField(labelWithString: "")

    init(settings: SettingsStore) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pastey Preferences"
        super.init(window: window)
        setupContentView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setupContentView() {
        guard let contentView = window?.contentView else { return }

        let retentionLabel = NSTextField(labelWithString: "Retention limit")
        retentionLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        retentionValueLabel.font = .systemFont(ofSize: 12)
        retentionValueLabel.textColor = .secondaryLabelColor

        retentionStepper.minValue = 10
        retentionStepper.maxValue = 1000
        retentionStepper.increment = 10
        retentionStepper.target = self
        retentionStepper.action = #selector(retentionChanged)

        let retentionRow = NSStackView(views: [retentionLabel, retentionValueLabel, retentionStepper])
        retentionRow.orientation = .horizontal
        retentionRow.alignment = .centerY
        retentionRow.spacing = 8

        let ignoreLabel = NSTextField(labelWithString: "Ignore list (bundle IDs, one per line)")
        ignoreLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        let ignoreHint = NSTextField(labelWithString: "Example: com.agilebits.onepassword8")
        ignoreHint.font = .systemFont(ofSize: 11)
        ignoreHint.textColor = .secondaryLabelColor

        ignoreTextView.isEditable = true
        ignoreTextView.font = .systemFont(ofSize: 12)
        ignoreTextView.delegate = self
        ignoreTextView.string = settings.ignoreListString()

        let ignoreScroll = NSScrollView()
        ignoreScroll.hasVerticalScroller = true
        ignoreScroll.borderType = .bezelBorder
        ignoreScroll.documentView = ignoreTextView

        let apiLabel = NSTextField(labelWithString: "Local API")
        apiLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        apiToggle.target = self
        apiToggle.action = #selector(apiToggleChanged)
        apiToggle.state = settings.localAPIEnabled ? .on : .off

        let portLabel = NSTextField(labelWithString: "Port")
        portLabel.font = .systemFont(ofSize: 11, weight: .medium)
        portLabel.textColor = .secondaryLabelColor

        apiPortField.delegate = self
        apiPortField.stringValue = "\(settings.localAPIPort)"
        apiPortField.font = .systemFont(ofSize: 12)
        apiPortField.alignment = .right
        apiPortField.maximumNumberOfLines = 1
        apiPortField.controlSize = .small

        let portRow = NSStackView(views: [portLabel, apiPortField])
        portRow.orientation = .horizontal
        portRow.alignment = .centerY
        portRow.spacing = 8

        apiHintLabel.font = .systemFont(ofSize: 11)
        apiHintLabel.textColor = .secondaryLabelColor
        apiHintLabel.lineBreakMode = .byWordWrapping
        apiHintLabel.maximumNumberOfLines = 0
        updateAPIHint()

        let apiStack = NSStackView(views: [apiLabel, apiToggle, portRow, apiHintLabel])
        apiStack.orientation = .vertical
        apiStack.spacing = 6

        let stack = NSStackView(views: [retentionRow, ignoreLabel, ignoreHint, ignoreScroll, apiStack])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            ignoreScroll.heightAnchor.constraint(equalToConstant: 160),
            apiPortField.widthAnchor.constraint(equalToConstant: 80)
        ])

        updateRetentionUI()
    }

    private func updateRetentionUI() {
        retentionStepper.integerValue = settings.retentionLimit
        retentionValueLabel.stringValue = "\(settings.retentionLimit) items"
    }

    private func updateAPIHint() {
        let status = settings.localAPIEnabled ? "Enabled" : "Disabled"
        apiHintLabel.stringValue = "\(status) · http://127.0.0.1:\(settings.localAPIPort)"
    }

    @objc private func retentionChanged() {
        settings.updateRetentionLimit(retentionStepper.integerValue)
        updateRetentionUI()
    }

    @objc private func apiToggleChanged() {
        settings.updateLocalAPIEnabled(apiToggle.state == .on)
        updateAPIHint()
    }

    func textDidChange(_ notification: Notification) {
        let lines = ignoreTextView.string.components(separatedBy: .newlines)
        settings.updateIgnoreList(lines)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let value = Int(apiPortField.stringValue) else { return }
        settings.updateLocalAPIPort(value)
        updateAPIHint()
    }
}
