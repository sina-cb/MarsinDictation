import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        
        DictationService.shared.start()
        
        // Hide dock icon completely since LSUIElement = true in Info.plist handles most of it,
        // but it's good practice.
        NSApp.setActivationPolicy(.accessory)
    }
}
