import AppKit
import Carbon

public class PasteboardInjector: ITextInjector {
    public init() {}
    
    public func inject(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        
        let previousItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let newItem = NSPasteboardItem()
            let types = item.types
            for type in types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        dispatchCmdV()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let items = previousItems, !items.isEmpty {
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            }
        }
        
        return true
    }
    
    private func dispatchCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9 // 'v'
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
