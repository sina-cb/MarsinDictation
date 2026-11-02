import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    private var localAPI: LocalTranscriptionApi?
    /// Safety net: uses the shared singleton so it restores the same state DictationService saved
    private var audioSilencer: AudioSilencer { AudioSilencer.shared }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        EnvLoader.load()
        
        // Check Accessibility (needed for auto-paste via CGEvent)
        if !AXIsProcessTrusted() {
            AutoPastePermission.request()
            print("[AppDelegate] ⚠️ Accessibility not granted — text copies to clipboard (⌘V to paste)")
        } else {
            print("[AppDelegate] ✅ Accessibility granted — auto-paste will work")
        }
        
        statusBarController = StatusBarController()
        
        startLocalAPI()
        DictationService.shared.start()
        
        // Hide dock icon completely since LSUIElement = true in Info.plist handles most of it,
        // but it's good practice.
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func startLocalAPI() {
        let settings = SettingsManager.shared
        let model = settings.whisperModel
        let language = settings.language
        let manager = WhisperModelManager.shared
        let available = manager.isModelAvailable(model)
        let client = WhisperTranscriptionClient.shared(modelURL: manager.modelURL(for: model))
        let config = TranscriptionConfig(endpoint: "", apiKey: nil, model: model, language: language)
        let api = LocalTranscriptionApi(model: model, language: language,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            modelAvailable: available, ready: { client.isModelLoaded },
            transcribe: { try await client.tryTranscribe(wavData: $0, config: config) })
        localAPI = api
        if !api.tryStart() { print("[LocalAPI] Port 6976 unavailable; desktop dictation continues") }
        if available {
            Task.detached {
                do { try client.loadModel() }
                catch { print("[LocalAPI] Existing embedded model could not load") }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Safety net: restore system audio if app terminates while dictation hotkey is held
        localAPI?.stop()
        audioSilencer.restore()
    }
}
