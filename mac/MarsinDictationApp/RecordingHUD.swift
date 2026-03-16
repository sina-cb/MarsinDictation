import SwiftUI
import AppKit

class RecordingHUDController {
    static let shared = RecordingHUDController()
    
    private var window: NSWindow?
    
    private init() {}
    
    func show(text: String, isRecording: Bool = true) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 250, height: 60),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.animationBehavior = .documentWindow
            
            window = panel
        }
        
        guard let window = window else { return }
        
        // Position at bottom center, or logic...
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = window.frame
            let x = screenRect.midX - (windowRect.width / 2)
            let y = screenRect.minY + 50
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        let rootView = RecordingHUDView(text: text, isRecording: isRecording)
        window.contentView = NSHostingView(rootView: rootView)
        
        window.orderFront(nil)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
}

struct RecordingHUDView: View {
    var text: String
    var isRecording: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isRecording ? Color(red: 76/255, green: 175/255, blue: 80/255) : Color.gray)
                .frame(width: 12, height: 12)
            
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 205/255, green: 214/255, blue: 244/255))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(red: 30/255, green: 30/255, blue: 46/255).opacity(0.85))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 2)
    }
}
