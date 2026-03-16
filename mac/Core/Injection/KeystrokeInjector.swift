import AppKit

/// Fallback injector: types text character-by-character via AppleScript.
/// Less reliable than PasteboardInjector, but works as a last resort.
public class KeystrokeInjector: ITextInjector {
    public init() {}
    
    public func inject(text: String) -> Bool {
        // Use AppleScript to type the text — more reliable than CGEvent for Unicode
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "\(escapedText)"
            end tell
        """)
        
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        
        if let error = error {
            print("[KeystrokeInjector] AppleScript error: \(error)")
            return false
        }
        
        return true
    }
}
