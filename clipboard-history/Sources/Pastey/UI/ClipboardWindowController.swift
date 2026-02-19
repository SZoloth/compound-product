import AppKit

@MainActor
final class ClipboardWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: ClipboardHistoryStore
    private let actions = ClipboardActions()
    private var filteredEntries: [ClipboardEntry] = []
    private var rows: [RowItem] = []

    private let searchField = NSSearchField()
    private let typeFilter = NSPopUpButton()
    private let tableView = ClipboardTableView()
    private let countLabel = NSTextField(labelWithString: "Clipboard items")
    private let previewImageView = NSImageView()
    private let previewTextView = NSTextView()
    private let infoStack = NSStackView()
    private let emptyStateLabel = NSTextField(labelWithString: "No clipboard items")
    private let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let actionsButton = NSButton(title: "Actions", target: nil, action: nil)
    private var previewImageHeightConstraint: NSLayoutConstraint?
    private var lastSelectedRow: Int?
    private let imageCache = NSCache<NSString, NSImage>()

    private let rowIdentifier = NSUserInterfaceItemIdentifier("ClipboardRow")
    private let groupIdentifier = NSUserInterfaceItemIdentifier("ClipboardGroupRow")
    private let backgroundIdentifier = NSUserInterfaceItemIdentifier("ClipboardRowBackground")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private enum RowItem {
        case group(String)
        case entry(ClipboardEntry)
    }

    init(store: ClipboardHistoryStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pastey"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        super.init(window: window)
        setupContentView()
        reloadData()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreUpdate),
            name: .clipboardHistoryDidUpdate,
            object: store
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setupContentView() {
        guard let contentView = window?.contentView else { return }

        let topBar = makeTopBar()
        let splitView = makeSplitView()
        let bottomBar = makeBottomBar()

        let container = NSStackView(views: [topBar, splitView, bottomBar])
        container.orientation = .vertical
        container.spacing = 10
        container.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func makeTopBar() -> NSView {
        let bar = makeVisualEffectView(material: .titlebar, cornerRadius: 10)

        let searchContainer = makePillContainer()
        searchField.placeholderString = "Type to filter entries..."
        searchField.delegate = self
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 13, weight: .medium)
        searchField.controlSize = .small
        searchField.sendsSearchStringImmediately = true
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchContainer.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor, constant: 4),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: -4)
        ])
        searchContainer.heightAnchor.constraint(equalToConstant: 28).isActive = true
        searchContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        let filterContainer = makePillContainer()
        typeFilter.addItems(withTitles: ["All Types", "Text", "Image", "File", "URL"])
        typeFilter.target = self
        typeFilter.action = #selector(handleFilterChange)
        typeFilter.controlSize = .small
        typeFilter.font = .systemFont(ofSize: 12, weight: .medium)
        typeFilter.isBordered = false
        typeFilter.translatesAutoresizingMaskIntoConstraints = false

        filterContainer.addSubview(typeFilter)
        NSLayoutConstraint.activate([
            typeFilter.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor, constant: 8),
            typeFilter.trailingAnchor.constraint(equalTo: filterContainer.trailingAnchor, constant: -8),
            typeFilter.topAnchor.constraint(equalTo: filterContainer.topAnchor, constant: 4),
            typeFilter.bottomAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: -4)
        ])
        filterContainer.heightAnchor.constraint(equalToConstant: 28).isActive = true
        filterContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

        let stack = NSStackView(views: [searchContainer, filterContainer])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        searchContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filterContainer.setContentHuggingPriority(.required, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8)
        ])

        return bar
    }

    private func makeSplitView() -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let leftPane = makeLeftPane()
        let rightPane = makeRightPane()

        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(rightPane)
        leftPane.widthAnchor.constraint(equalToConstant: 320).isActive = true
        splitView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        return splitView
    }

    private func makeLeftPane() -> NSView {
        let leftPane = makeVisualEffectView(material: .sidebar, cornerRadius: 8)

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [countLabel])
        headerStack.orientation = .vertical
        headerStack.spacing = 2
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ClipboardColumn"))
        column.title = "Items"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.backgroundColor = .clear
        tableView.onEnter = { [weak self] in
            self?.pasteSelected()
        }
        tableView.onDelete = { [weak self] in
            self?.deleteSelected()
        }
        tableView.onActions = { [weak self] in
            self?.showActionsMenu()
        }
        tableView.onFocusSearch = { [weak self] in
            self?.focusSearch()
        }

        scrollView.documentView = tableView
        scrollView.drawsBackground = false

        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        leftPane.addSubview(headerStack)
        leftPane.addSubview(scrollView)
        leftPane.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor, constant: 8),
            headerStack.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: -8),
            headerStack.topAnchor.constraint(equalTo: leftPane.topAnchor, constant: 8),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor)
        ])

        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        return leftPane
    }

    private func makeRightPane() -> NSView {
        let rightPane = makeVisualEffectView(material: .contentBackground, cornerRadius: 8)

        let detailTitle = NSTextField(labelWithString: "Preview")
        detailTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        detailTitle.textColor = .secondaryLabelColor
        detailTitle.translatesAutoresizingMaskIntoConstraints = false

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.translatesAutoresizingMaskIntoConstraints = false

        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.font = .systemFont(ofSize: 12)
        previewTextView.textColor = .labelColor
        previewTextView.drawsBackground = false
        previewTextView.textContainerInset = NSSize(width: 4, height: 6)

        let previewScroll = NSScrollView()
        previewScroll.hasVerticalScroller = true
        previewScroll.drawsBackground = false
        previewScroll.backgroundColor = .clear
        previewScroll.documentView = previewTextView
        previewScroll.translatesAutoresizingMaskIntoConstraints = false

        infoStack.orientation = .vertical
        infoStack.spacing = 4
        infoStack.alignment = .leading
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = NSStackView(views: [detailTitle, previewImageView, previewScroll, infoStack])
        rightStack.orientation = .vertical
        rightStack.spacing = 10
        rightStack.alignment = .leading
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        rightPane.addSubview(rightStack)

        previewImageHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 240)
        previewImageHeightConstraint?.priority = .defaultHigh
        previewImageHeightConstraint?.isActive = true
        previewScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        previewScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        previewScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        infoStack.setContentHuggingPriority(.required, for: .vertical)
        infoStack.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            rightStack.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor, constant: 8),
            rightStack.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor, constant: -8),
            rightStack.topAnchor.constraint(equalTo: rightPane.topAnchor, constant: 8),
            rightStack.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor, constant: -8)
        ])

        return rightPane
    }

    private func makeBottomBar() -> NSView {
        let bar = makeVisualEffectView(material: .titlebar, cornerRadius: 8)

        let featureLabel = NSTextField(labelWithString: "Pastey")
        featureLabel.font = .systemFont(ofSize: 12)
        featureLabel.textColor = .secondaryLabelColor

        pasteButton.target = self
        pasteButton.action = #selector(pasteSelected)
        copyButton.target = self
        copyButton.action = #selector(copySelected)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        actionsButton.target = self
        actionsButton.action = #selector(showActionsMenu)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttons = NSStackView(views: [pasteButton, copyButton, deleteButton, actionsButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6

        let stack = NSStackView(views: [featureLabel, spacer, buttons])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8)
        ])

        return bar
    }

    @objc private func handleFilterChange() {
        reloadData()
    }

    @objc private func handleStoreUpdate() {
        reloadData()
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadData()
    }

    private func reloadData() {
        let selectedId = selectedEntry()?.item.id
        let term = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedType = selectedFilterType()
        let allEntries = store.entries
        filteredEntries = allEntries.filter { entry in
            let matchesType = selectedType == nil || entry.item.type == selectedType
            let matchesSearch: Bool
            if term.isEmpty {
                matchesSearch = true
            } else {
                let values = [
                    entry.item.previewTitle,
                    entry.content.text ?? "",
                    entry.content.url?.absoluteString ?? "",
                    entry.content.fileURL?.path ?? "",
                    entry.item.sourceAppName ?? ""
                ].map { $0.lowercased() }
                matchesSearch = values.contains(where: { $0.contains(term) })
            }
            return matchesType && matchesSearch
        }
        rows = buildRows(entries: filteredEntries)
        let itemCount = filteredEntries.count
        let countText = itemCount == 1 ? "1 item" : "\(itemCount) items"
        countLabel.stringValue = "Clipboard items · \(countText)"
        if filteredEntries.isEmpty {
            emptyStateLabel.isHidden = false
            emptyStateLabel.stringValue = store.entries.isEmpty ? "No clipboard items yet" : "No results"
        } else {
            emptyStateLabel.isHidden = true
        }
        tableView.reloadData()
        if let selectedId, let rowIndex = rowIndex(for: selectedId) {
            tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        } else {
            ensureValidSelection()
        }
        updateDetail()
    }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    private func selectedFilterType() -> ClipboardItemType? {
        switch typeFilter.titleOfSelectedItem {
        case "Text": return .text
        case "Image": return .image
        case "File": return .file
        case "URL": return .url
        default: return nil
        }
    }

    private func selectedEntry() -> ClipboardEntry? {
        let row = tableView.selectedRow
        guard row >= 0, rows.indices.contains(row) else { return nil }
        if case let .entry(entry) = rows[row] {
            return entry
        }
        return nil
    }

    private func buildRows(entries: [ClipboardEntry]) -> [RowItem] {
        guard !entries.isEmpty else { return [] }
        var result: [RowItem] = []
        let pinned = entries.filter { $0.item.pinned }
        let unpinned = entries.filter { !$0.item.pinned }

        if !pinned.isEmpty {
            result.append(.group("Pinned"))
            result.append(contentsOf: pinned.map { .entry($0) })
        }

        let calendar = Calendar.current
        var lastDay: Date?
        for entry in unpinned {
            let day = calendar.startOfDay(for: entry.item.createdAt)
            if lastDay == nil || lastDay != day {
                result.append(.group(sectionTitle(for: entry.item.createdAt)))
                lastDay = day
            }
            result.append(.entry(entry))
        }
        return result
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func firstEntryRowIndex() -> Int? {
        rows.firstIndex { row in
            if case .entry = row { return true }
            return false
        }
    }

    private func rowIndex(for id: UUID) -> Int? {
        rows.firstIndex { row in
            if case let .entry(entry) = row {
                return entry.item.id == id
            }
            return false
        }
    }

    private func ensureValidSelection() {
        if rows.isEmpty {
            tableView.deselectAll(nil)
            return
        }

        let selected = tableView.selectedRow
        if selected < 0 || selected >= rows.count {
            selectNearestEntry(from: 0)
            return
        }
        if case .group = rows[selected] {
            selectNearestEntry(from: selected)
        }
    }

    private func selectNearestEntry(from index: Int) {
        if rows.isEmpty {
            tableView.deselectAll(nil)
            return
        }

        if let forward = (index..<rows.count).first(where: { idx in
            if case .entry = rows[idx] { return true }
            return false
        }) {
            tableView.selectRowIndexes(IndexSet(integer: forward), byExtendingSelection: false)
            return
        }

        if let backward = (0..<index).reversed().first(where: { idx in
            if case .entry = rows[idx] { return true }
            return false
        }) {
            tableView.selectRowIndexes(IndexSet(integer: backward), byExtendingSelection: false)
            return
        }

        tableView.deselectAll(nil)
    }

    private func updateDetail() {
        guard let entry = selectedEntry() else {
            previewImageView.image = nil
            previewTextView.string = "Select an item"
            clearInfoStack()
            previewImageHeightConstraint?.constant = 0
            return
        }

        if let cached = imageCache.object(forKey: entry.item.id.uuidString as NSString) {
            previewImageView.image = cached
            previewImageHeightConstraint?.constant = 240
        } else if let data = entry.content.imageData, let image = NSImage(data: data) {
            imageCache.setObject(image, forKey: entry.item.id.uuidString as NSString)
            previewImageView.image = image
            previewImageHeightConstraint?.constant = 240
        } else if let path = entry.content.imagePath, let image = NSImage(contentsOfFile: path) {
            imageCache.setObject(image, forKey: entry.item.id.uuidString as NSString)
            previewImageView.image = image
            previewImageHeightConstraint?.constant = 240
        } else {
            previewImageView.image = nil
            previewImageHeightConstraint?.constant = 0
        }

        if let text = entry.content.text, !text.isEmpty {
            previewTextView.string = text
        } else if let url = entry.content.url {
            previewTextView.string = url.absoluteString
        } else if let fileURL = entry.content.fileURL {
            previewTextView.string = fileURL.path
        } else {
            previewTextView.string = entry.item.previewTitle
        }

        updateInfo(entry)
    }

    private func updateInfo(_ entry: ClipboardEntry) {
        clearInfoStack()
        let created = dateFormatter.string(from: entry.item.createdAt)
        var info: [(String, String)] = [
            ("Type", entry.item.type.rawValue),
            ("Created", created)
        ]
        if entry.item.pinned {
            info.append(("Pinned", "Yes"))
        }
        if let source = entry.item.sourceAppName {
            info.append(("Source", source))
        }
        if let bundle = entry.item.sourceAppBundleId {
            info.append(("Bundle ID", bundle))
        }
        info.append(contentsOf: entry.item.metadata.map { ($0.key.capitalized, $0.value) })

        for (label, value) in info {
            let line = NSTextField(labelWithString: "\(label): \(value)")
            line.font = .systemFont(ofSize: 12)
            line.textColor = .secondaryLabelColor
            infoStack.addArrangedSubview(line)
        }
    }

    private func clearInfoStack() {
        for view in infoStack.arrangedSubviews {
            infoStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    @objc private func pasteSelected() {
        guard let entry = selectedEntry() else { return }
        actions.paste(entry)
    }

    @objc private func pastePlainSelected() {
        guard let entry = selectedEntry() else { return }
        actions.pastePlain(entry)
    }

    @objc private func copySelected() {
        guard let entry = selectedEntry() else { return }
        actions.copy(entry)
    }

    @objc private func togglePinSelected() {
        guard let entry = selectedEntry() else { return }
        store.togglePinned(id: entry.item.id)
    }

    @objc private func deleteSelected() {
        guard let entry = selectedEntry() else { return }
        let row = tableView.selectedRow
        store.delete(id: entry.item.id)
        reloadData()
        if row >= 0 {
            selectNearestEntry(from: row)
        }
    }

    @objc private func showActionsMenu() {
        let menu = NSMenu()
        let hasSelection = selectedEntry() != nil

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteSelected), keyEquivalent: "\r")
        pasteItem.target = self
        pasteItem.isEnabled = hasSelection
        menu.addItem(pasteItem)

        let pastePlainItem = NSMenuItem(title: "Paste Plain", action: #selector(pastePlainSelected), keyEquivalent: "p")
        pastePlainItem.target = self
        pastePlainItem.keyEquivalentModifierMask = [.command, .shift]
        pastePlainItem.isEnabled = hasSelection
        menu.addItem(pastePlainItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copySelected), keyEquivalent: "c")
        copyItem.target = self
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        let pinTitle = selectedEntry()?.item.pinned == true ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinSelected), keyEquivalent: "p")
        pinItem.target = self
        pinItem.keyEquivalentModifierMask = [.command, .option]
        pinItem.isEnabled = hasSelection
        menu.addItem(pinItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: "\u{8}")
        deleteItem.target = self
        deleteItem.isEnabled = hasSelection
        menu.addItem(deleteItem)

        let buttonFrame = actionsButton.bounds
        let position = NSPoint(x: 0, y: buttonFrame.height + 4)
        menu.popUp(positioning: nil, at: position, in: actionsButton)
    }

    // MARK: NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rowItem = rows[row]
        if case let .group(title) = rowItem {
            if let cell = tableView.makeView(withIdentifier: groupIdentifier, owner: self) as? NSTableCellView {
                cell.textField?.stringValue = title
                return cell
            }
            let cell = NSTableCellView()
            cell.identifier = groupIdentifier
            let titleField = NSTextField(labelWithString: title.uppercased())
            titleField.font = .systemFont(ofSize: 10.5, weight: .semibold)
            titleField.textColor = .tertiaryLabelColor
            titleField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(titleField)
            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                titleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.textField = titleField
            return cell
        }

        guard case let .entry(entry) = rowItem else { return nil }
        if let cell = tableView.makeView(withIdentifier: rowIdentifier, owner: self) as? NSTableCellView {
            configureCell(cell, entry: entry, isSelected: tableView.selectedRow == row)
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = rowIdentifier

        let backgroundView = NSView()
        backgroundView.identifier = backgroundIdentifier
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 8
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .labelColor
        iconView.tag = 3

        let titleField = NSTextField(labelWithString: "")
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.tag = 1
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitleField = NSTextField(labelWithString: "")
        subtitleField.font = .systemFont(ofSize: 10.5, weight: .medium)
        subtitleField.textColor = .tertiaryLabelColor
        subtitleField.tag = 2

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.orientation = .vertical
        textStack.spacing = 2

        let rowStack = NSStackView(views: [iconView, textStack])
        rowStack.orientation = .horizontal
        rowStack.spacing = 8
        rowStack.alignment = .centerY
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(backgroundView)
        cell.addSubview(rowStack)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            backgroundView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            backgroundView.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
            backgroundView.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -3),

            rowStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            rowStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            rowStack.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
            rowStack.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -6),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])

        cell.textField = titleField
        configureCell(cell, entry: entry, isSelected: tableView.selectedRow == row)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let newRow = tableView.selectedRow
        var rowsToReload = IndexSet()
        if let lastSelectedRow, lastSelectedRow >= 0 {
            rowsToReload.insert(lastSelectedRow)
        }
        if newRow >= 0 {
            rowsToReload.insert(newRow)
        }
        lastSelectedRow = newRow
        if !rowsToReload.isEmpty {
            tableView.reloadData(forRowIndexes: rowsToReload, columnIndexes: IndexSet(integer: 0))
        }
        updateDetail()
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .group = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .group = rows[row] { return 22 }
        return 46
    }

    private func configureCell(_ cell: NSTableCellView, entry: ClipboardEntry, isSelected: Bool) {
        let titleField = cell.viewWithTag(1) as? NSTextField
        let subtitleField = cell.viewWithTag(2) as? NSTextField
        let iconView = cell.viewWithTag(3) as? NSImageView
        let backgroundView = cell.subviews.first { $0.identifier == backgroundIdentifier }

        titleField?.stringValue = entry.item.previewTitle
        let source = entry.item.sourceAppName ?? "Unknown"
        let time = timeFormatter.string(from: entry.item.createdAt)
        let pinLabel = entry.item.pinned ? "Pinned · " : ""
        subtitleField?.stringValue = "\(pinLabel)\(source) · \(time)"
        iconView?.image = icon(for: entry.item.type)
        if let backgroundView {
            backgroundView.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor : NSColor.clear.cgColor
        }
    }

    private func icon(for type: ClipboardItemType) -> NSImage? {
        let symbolName: String
        switch type {
        case .text:
            symbolName = "text.alignleft"
        case .url:
            symbolName = "link"
        case .image:
            symbolName = "photo"
        case .file:
            symbolName = "doc"
        case .unknown:
            symbolName = "questionmark"
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    private func makeVisualEffectView(material: NSVisualEffectView.Material, cornerRadius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    private func makePillContainer() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        view.layer?.borderWidth = 1
        return view
    }
}
