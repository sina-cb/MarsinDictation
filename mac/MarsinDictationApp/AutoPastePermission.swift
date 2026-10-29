import AppKit
import ApplicationServices

/// Trust belongs to the installed app's signing identity; a saved "prompted" flag cannot replace it.
enum AutoPastePermission {
    static func request(openSettings: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if openSettings {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
