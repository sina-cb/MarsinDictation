import SwiftUI
import AppKit

enum ToastType {
    case recording
    case transcribing
    case success
    case error
    case idle
}

class RecordingHUDController {
    static let shared = RecordingHUDController()
    
    private var window: NSPanel?
    private var hideTimer: Timer?
    private var hostingView: NSHostingView<RecordingHUDView>?
    
    private init() {}
    
    func showToast(text: String, type: ToastType, duration: Double? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let view = RecordingHUDView(text: text, type: type)
            
            if self.window == nil {
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 280, height: 50),
                    styleMask: [.nonactivatingPanel, .borderless],
                    backing: .buffered,
                    defer: false
                )
                
                panel.isFloatingPanel = true
                panel.level = .floating
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.animationBehavior = .utilityWindow
                panel.ignoresMouseEvents = true
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 50)
                panel.contentView = hosting
                
                self.hostingView = hosting
                self.window = panel
            } else {
                // Update existing view instead of replacing contentView
                self.hostingView?.rootView = view
            }
            
            guard let window = self.window else { return }
            
            // Position at bottom center
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let x = screenRect.midX - 140
                let y = screenRect.minY + 60
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            window.orderFront(nil)
            
            // Cancel previous timer
            self.hideTimer?.invalidate()
            self.hideTimer = nil
            
            // Auto-hide based on type
            let hideDuration: Double?
            switch type {
            case .recording, .transcribing:
                hideDuration = nil  // Stay visible
            default:
                hideDuration = duration ?? 2.0
            }
            
            if let d = hideDuration {
                self.hideTimer = Timer.scheduledTimer(withTimeInterval: d, repeats: false) { [weak self] _ in
                    self?.hide()
                }
            }
        }
    }
    
    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.hideTimer?.invalidate()
            self?.hideTimer = nil
            self?.window?.orderOut(nil)
        }
    }
}

struct RecordingHUDView: View {
    var text: String
    var type: ToastType
    
    private var dotColor: Color {
        switch type {
        case .recording:
            return Color(red: 243/255, green: 139/255, blue: 168/255)
        case .transcribing:
            return Color(red: 137/255, green: 180/255, blue: 250/255)
        case .success:
            return Color(red: 76/255, green: 175/255, blue: 80/255)
        case .error:
            return Color(red: 249/255, green: 226/255, blue: 175/255)
        case .idle:
            return Color.gray
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 12, height: 12)
            
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 205/255, green: 214/255, blue: 244/255))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(red: 30/255, green: 30/255, blue: 46/255).opacity(0.87))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 2)
        .frame(width: 280, height: 50)
    }
}
