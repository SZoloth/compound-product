import AppKit

final class ClipboardTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?
    var onActions: (() -> Void)?
    var onFocusSearch: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "k":
                onActions?()
                return
            case "f":
                onFocusSearch?()
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 36: // Return
            onEnter?()
        case 51: // Delete
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }
}
