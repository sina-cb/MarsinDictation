import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    /// Safety net: uses the shared singleton so it restores the same state DictationService saved
    private var audioSilencer: AudioSilencer { AudioSilencer.shared }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        EnvLoader.load()
        
        // Check Accessibility (needed for auto-paste via CGEvent)
        if !AXIsProcessTrusted() {
            let hasPrompted = UserDefaults.standard.bool(forKey: "hasPromptedAccessibility")
            if !hasPrompted {
                // First launch: show system prompt
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
                UserDefaults.standard.set(true, forKey: "hasPromptedAccessibility")
            }
            print("[AppDelegate] ⚠️ Accessibility not granted — text copies to clipboard (⌘V to paste)")
        } else {
            print("[AppDelegate] ✅ Accessibility granted — auto-paste will work")
        }
        
        statusBarController = StatusBarController()
        
        DictationService.shared.start()
        
        // Hide dock icon completely since LSUIElement = true in Info.plist handles most of it,
        // but it's good practice.
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Safety net: restore system audio if app terminates while dictation hotkey is held
        audioSilencer.restore()
    }
}
