import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class ClipboardActions {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ entry: ClipboardEntry) {
        write(entry)
    }

    func paste(_ entry: ClipboardEntry) {
        write(entry)
        guard ensureAccessibilityPermission() else {
            showAccessibilityAlert()
            return
        }
        sendPasteKeystroke()
    }

    func pastePlain(_ entry: ClipboardEntry) {
        writePlain(entry)
        guard ensureAccessibilityPermission() else {
            showAccessibilityAlert()
            return
        }
        sendPasteKeystroke()
    }

    private func write(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        if let imageData = entry.content.imageData, let image = NSImage(data: imageData) {
            pasteboard.writeObjects([image])
            return
        }
        if let fileURL = entry.content.fileURL {
            pasteboard.writeObjects([fileURL as NSURL])
            return
        }
        if let url = entry.content.url {
            pasteboard.setString(url.absoluteString, forType: .string)
            pasteboard.setString(url.absoluteString, forType: NSPasteboard.PasteboardType("public.url"))
            return
        }
        if let text = entry.content.text {
            pasteboard.setString(text, forType: .string)
        }
    }

    private func writePlain(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        if let text = entry.content.text {
            pasteboard.setString(text, forType: .string)
            return
        }
        if let url = entry.content.url {
            pasteboard.setString(url.absoluteString, forType: .string)
        }
    }

    private func ensureAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [promptKey: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    private func sendPasteKeystroke() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyV: CGKeyCode = 0x09
        let keyCommand: CGKeyCode = 0x37

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: keyCommand, keyDown: true)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: keyCommand, keyDown: false)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        commandDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Enable Accessibility permissions for Clipboard History to paste into other apps."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
