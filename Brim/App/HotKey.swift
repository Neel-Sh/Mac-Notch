import Carbon.HIToolbox

/// One system-wide shortcut. Carbon's hot keys need no Accessibility permission, unlike event taps.
final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func set(_ shortcut: ToggleShortcut) {
        unregister()
        guard let (key, modifiers) = Self.code(for: shortcut) else { return }

        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &type, context, &handler)

        let id = EventHotKeyID(signature: OSType(0x4252_494D), id: 1) // "BRIM"
        RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private static func code(for shortcut: ToggleShortcut) -> (UInt32, UInt32)? {
        switch shortcut {
        case .off: nil
        case .optionCommandB: (UInt32(kVK_ANSI_B), UInt32(optionKey | cmdKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .controlCommandN: (UInt32(kVK_ANSI_N), UInt32(controlKey | cmdKey))
        }
    }
}
