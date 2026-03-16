import AppKit

public class KeystrokeInjector: ITextInjector {
    public init() {}
    
    public func inject(text: String) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16Chars = Array(text.utf16)
        
        for char in utf16Chars {
            var keyCode = char
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &keyCode)
            event?.post(tap: .cghidEventTap)
            
            let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            eventUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &keyCode)
            eventUp?.post(tap: .cghidEventTap)
        }
        
        return true
    }
}
