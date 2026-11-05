import Carbon.HIToolbox
import Core

/// Registers global hotkeys with Carbon `RegisterEventHotKey` (PDR §4.3).
/// Needs no Accessibility or Input Monitoring permission.
@MainActor
final class HotkeyManager {
    private static let signature: OSType = 0x4F6D_5745 // 'OmWE'

    private var handlerRef: EventHandlerRef?
    private var active: [UInt32: (registration: HotkeyRegistration, ref: EventHotKeyRef)] = [:]
    private var current: [HotkeyRegistration] = []
    private var nextID: UInt32 = 1

    /// Registrations Carbon refused (chord taken by another app, …).
    private(set) var failures: [HotkeyRegistration] = []

    var onPress: ((HotkeyRegistration) -> Void)?

    init() {
        let unmapped = CarbonKeys.unmappedKeys
        if !unmapped.isEmpty {
            Log.hotkeys.fault("No Carbon key code for: \(unmapped.sorted().joined(separator: ", "), privacy: .public)")
        }
    }

    /// Replaces all registrations. No-op when nothing changed.
    func apply(_ registrations: [HotkeyRegistration]) {
        guard registrations != current else { return }
        unregisterAll()
        installHandlerIfNeeded()
        current = registrations
        failures = []

        for registration in registrations {
            guard let keyCode = CarbonKeys.keyCode(for: registration.resolved.key) else {
                failures.append(registration)
                continue
            }
            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode, CarbonKeys.modifierFlags(registration.resolved.modifiers),
                EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                active[id] = (registration, ref)
                Log.hotkeys.info("Registered \(registration.hotkey.description, privacy: .public) → \(registration.action.description, privacy: .public)")
            } else {
                failures.append(registration)
                Log.hotkeys.error("Couldn't register \(registration.hotkey.description, privacy: .public) (OSStatus \(status))")
            }
        }
    }

    func unregisterAll() {
        for (_, entry) in active { UnregisterEventHotKey(entry.ref) }
        active = [:]
        current = []
    }

    fileprivate func handle(id: UInt32) {
        guard let registration = active[id]?.registration else { return }
        onPress?(registration)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        if status != noErr {
            Log.hotkeys.error("InstallEventHandler failed (OSStatus \(status))")
        }
    }
}

/// Carbon callback; delivered on the main thread via the application event target.
private func hotKeyEventHandler(_: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    // The pointer itself isn't Sendable; its address is. The callback already runs on the main thread.
    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue().handle(id: id)
    }
    return noErr
}
