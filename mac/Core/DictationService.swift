import Foundation

public class DictationService: HotkeyDelegate, AudioCaptureDelegate {
    public static let shared = DictationService()
    
    private let hotkeyManager = HotkeyManager.shared
    private let audioCapture = AudioCapture()
    private let client = GenericTranscriptionClient()
    
    private let pasteboardInjector = PasteboardInjector()
    private let keystrokeInjector = KeystrokeInjector()
    
    private var isRecording = false
    
    private init() {
        hotkeyManager.delegate = self
        audioCapture.delegate = self
    }
    
    public func start() {
        print("[DictationService] Starting...")
        hotkeyManager.startMonitoring()
    }
    
    // MARK: - HotkeyDelegate
    public func dictationHotkeyToggled() {
        if hotkeyManager.isForegroundAppExcluded(exclusionList: []) {
            print("[DictationService] Foreground app excluded — ignoring hotkey")
            return
        }
        
        if isRecording {
            print("[DictationService] Stopping recording...")
            stopRecording()
        } else {
            print("[DictationService] Starting recording...")
            startRecording()
        }
    }
    
    public func recoveryHotkeyPressed() {
        if hotkeyManager.isForegroundAppExcluded(exclusionList: []) {
            return
        }
        
        if let pending = TranscriptStore.shared.popPending() {
            _ = executeInjectionLadder(text: pending.text)
        } else if let last = TranscriptStore.shared.getLastSuccessful() {
            _ = executeInjectionLadder(text: last.text)
        }
    }
    
    // MARK: - Audio
    private func startRecording() {
        audioCapture.requestMicrophonePermission { [weak self] granted in
            print("[DictationService] Mic permission granted: \(granted)")
            guard granted else {
                print("[DictationService] ❌ Mic permission denied — cannot record")
                return
            }
            self?.isRecording = true
            NotificationCenter.default.post(name: NSNotification.Name("RecordStateChanged"), object: true)
            self?.audioCapture.startCapture()
        }
    }
    
    private func stopRecording() {
        isRecording = false
        NotificationCenter.default.post(name: NSNotification.Name("RecordStateChanged"), object: false)
        audioCapture.stopCapture()
    }
    
    public func captureFailed(error: Error) {
        print("[DictationService] ❌ Capture failed: \(error.localizedDescription)")
        stopRecording()
    }
    
    public func readyToProcessWav(wavData: Data) {
        print("[DictationService] WAV ready: \(wavData.count) bytes — sending to API...")
        Task {
            do {
                let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
                print("[DictationService] API Key present: \(apiKey != nil)")
                let config = TranscriptionConfig(endpoint: "https://api.openai.com/v1/audio/transcriptions", apiKey: apiKey, model: "whisper-1", language: "en")
                let rawText = try await client.transcribe(wavData: wavData, config: config)
                print("[DictationService] ✅ Transcription: \(rawText)")
                let cleaned = TextPostProcessor.process(rawText)
                
                let success = executeInjectionLadder(text: cleaned)
                print("[DictationService] Injection success: \(success)")
                
                let transcript = Transcript(text: cleaned, provider: "openai", model: config.model, state: success ? .success : .pending)
                TranscriptStore.shared.save(transcript)
                
            } catch {
                print("[DictationService] ❌ Transcription error: \(error)")
                let transcript = Transcript(text: "", provider: "openai", model: "whisper-1", state: .failed_transcription)
                TranscriptStore.shared.save(transcript)
            }
        }
    }
    
    private func executeInjectionLadder(text: String) -> Bool {
        if pasteboardInjector.inject(text: text) {
            return true
        }
        if keystrokeInjector.inject(text: text) {
            return true
        }
        return false
    }
}
