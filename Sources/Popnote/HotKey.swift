import Carbon

/// A system-wide keyboard shortcut, via Carbon's RegisterEventHotKey
/// (still the standard way to do this on macOS; needs no permissions).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x504F_504E), id: 1) // "POPN"
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
        guard installed == noErr, registered == noErr else { return nil }
    }

    /// Whether macOS itself uses these keys (Spotlight, Mission Control, input
    /// sources…), per System Settings › Keyboard › Keyboard Shortcuts. Other
    /// apps' shortcuts can't be checked: macOS lets several apps register the
    /// same one, and doesn't say who has what.
    static func isSystemShortcut(keyCode: Int, modifiers: Int) -> Bool {
        var ref: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&ref) == noErr,
              let list = ref?.takeRetainedValue() as? [[String: Any]] else { return false }
        let relevant = cmdKey | optionKey | controlKey | shiftKey
        return list.contains { hotKey in
            (hotKey[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && hotKey[kHISymbolicHotKeyCode as String] as? Int == keyCode
                && (hotKey[kHISymbolicHotKeyModifiers as String] as? Int).map { $0 & relevant } == modifiers & relevant
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
