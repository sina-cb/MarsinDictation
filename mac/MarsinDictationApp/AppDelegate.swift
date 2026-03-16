import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        EnvLoader.load()
        
        // Request Accessibility (needed for auto-paste via CGEvent)
        // This prompts ONCE per binary — user toggles ON in System Settings
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            print("[AppDelegate] ✅ Accessibility granted — auto-paste will work")
        } else {
            print("[AppDelegate] ⚠️ Accessibility not yet granted — toggle ON in System Settings, then restart app. Until then, text copies to clipboard (⌘V to paste)")
        }
        
        statusBarController = StatusBarController()
        
        DictationService.shared.start()
        
        // Hide dock icon completely since LSUIElement = true in Info.plist handles most of it,
        // but it's good practice.
        NSApp.setActivationPolicy(.accessory)
    }
}
