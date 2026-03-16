import AppKit

public class PasteboardInjector: ITextInjector {
    public init() {}
    
    public func inject(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        
        // 1. Save current pasteboard contents (best-effort)
        let changeCount = pasteboard.changeCount
        let previousItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        // 2. Set pasteboard to transcribed text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 3. If Accessibility is granted, auto-paste via CGEvent
        if AXIsProcessTrusted() {
            Thread.sleep(forTimeInterval: 0.05)
            dispatchCmdVViaCGEvent()
            
            // Restore pasteboard after target app reads it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if pasteboard.changeCount == changeCount + 1 {
                    if let items = previousItems, !items.isEmpty {
                        pasteboard.clearContents()
                        pasteboard.writeObjects(items)
                    }
                }
            }
            
            print("[PasteboardInjector] ✅ Auto-pasted via CGEvent")
            return true
        }
        
        // 4. No Accessibility — text is on pasteboard, user pastes manually
        print("[PasteboardInjector] 📋 Text copied to pasteboard (no Accessibility — press ⌘V)")
        return true  // Return true because the text IS accessible via Cmd+V
    }
    
    private func dispatchCmdVViaCGEvent() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
