import Carbon

final class HotkeyManager {
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CHHK"), id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handler()
            return noErr
        }
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType, userData, &eventHandlerRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}

private func fourCharCode(_ code: String) -> OSType {
    var result: UInt32 = 0
    for scalar in code.utf8 {
        result = (result << 8) + UInt32(scalar)
    }
    return OSType(result)
}
