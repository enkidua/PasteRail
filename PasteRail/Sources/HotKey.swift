import Carbon
import Foundation

@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let instance = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in instance.action() }
            return noErr
        }, 1, &eventType, pointer, &handler)
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052414C), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
