import Cocoa

public protocol HotkeyDelegate: AnyObject {
    func dictationHotkeyToggled()
    func recoveryHotkeyPressed()
}

/// Uses NSEvent global + local monitors — no Accessibility permission required.
public class HotkeyManager {
    public static let shared = HotkeyManager()
    public weak var delegate: HotkeyDelegate?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    private init() {}
    
    public func startMonitoring() {
        // Global monitor: fires when OTHER apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event, source: "GLOBAL")
        }
        
        // Local monitor: fires when THIS app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event, source: "LOCAL")
            return event
        }
        
        print("[HotkeyManager] ✅ Monitors installed. Option+Space (dictation), Option+Z (recovery)")
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
    
    private func handleKeyEvent(_ event: NSEvent, source: String) {
        // Only process keyDown events (not flagsChanged)
        guard event.type == .keyDown else { return }
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Debug: log every keyDown so we can verify the monitor is working
        print("[HotkeyManager] [\(source)] keyCode=\(event.keyCode) flags=\(flags.rawValue)")
        
        // Option + Space  →  toggle dictation
        if event.keyCode == 49 && flags == .option {
            print("[HotkeyManager] 🎙️ DICTATION HOTKEY DETECTED")
            DispatchQueue.main.async {
                self.delegate?.dictationHotkeyToggled()
            }
        }
        
        // Option + Z  →  recovery paste
        if event.keyCode == 6 && flags == .option {
            print("[HotkeyManager] 🔄 RECOVERY HOTKEY DETECTED")
            DispatchQueue.main.async {
                self.delegate?.recoveryHotkeyPressed()
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
