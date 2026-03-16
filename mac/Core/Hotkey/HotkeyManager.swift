import Cocoa

public protocol HotkeyDelegate: AnyObject {
    func dictationHotkeyPressed()
    func dictationHotkeyReleased()
    func recoveryHotkeyPressed()
}

/// Uses NSEvent global + local monitors for modifier-based hotkeys.
/// Control+Option (modifier-only) does NOT require Accessibility permission.
/// Command+Shift+Z requires Accessibility for keyDown global monitoring.
public class HotkeyManager {
    public static let shared = HotkeyManager()
    public weak var delegate: HotkeyDelegate?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    /// Tracks whether the dictation combo is currently held
    private var isHolding = false
    
    private init() {}
    
    public func startMonitoring() {
        // Global monitor: fires when OTHER apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event, source: "GLOBAL")
        }
        
        // Local monitor: fires when THIS app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event, source: "LOCAL")
            return event
        }
        
        print("[HotkeyManager] ✅ Monitors installed. Control+Option HOLD (dictation), ⌘⇧Z (recovery)")
    }
    
    public func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    private func handleEvent(_ event: NSEvent, source: String) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        if event.type == .flagsChanged {
            let dictationCombo: NSEvent.ModifierFlags = [.control, .option]
            
            if flags == dictationCombo && !isHolding {
                // Control+Option pressed — start recording
                isHolding = true
                print("[HotkeyManager] 🎙️ HOLD START (Control+Option pressed)")
                DispatchQueue.main.async {
                    self.delegate?.dictationHotkeyPressed()
                }
            } else if isHolding && flags != dictationCombo {
                // Modifiers released — stop recording
                isHolding = false
                print("[HotkeyManager] 🛑 HOLD END (Control+Option released)")
                DispatchQueue.main.async {
                    self.delegate?.dictationHotkeyReleased()
                }
            }
        }
        
        if event.type == .keyDown {
            // Command+Shift+Z → recovery paste
            if event.keyCode == 6 && flags == [.command, .shift] {
                print("[HotkeyManager] 🔄 RECOVERY HOTKEY DETECTED (⌘⇧Z)")
                DispatchQueue.main.async {
                    self.delegate?.recoveryHotkeyPressed()
                }
            }
        }
    }
    
    public func isForegroundAppExcluded(exclusionList: [String]) -> Bool {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontmost.bundleIdentifier {
            return exclusionList.contains(bundleId)
        }
        return false
    }
    
    deinit {
        stopMonitoring()
    }
}
