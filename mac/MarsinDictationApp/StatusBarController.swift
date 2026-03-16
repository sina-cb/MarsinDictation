import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private let menu = NSMenu()
    
    init() {
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Marsin Dictation")
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        
        let quitItem = NSMenuItem(title: "Quit Marsin Dictation", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func openSettings() {
        // App settings window is managed by SwiftUI Scene
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
