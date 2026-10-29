import Foundation
import AVFoundation
import AppKit
import ApplicationServices

public class DictationService: HotkeyDelegate, AudioCaptureDelegate {
    public static let shared = DictationService()
    
    private let hotkeyManager = HotkeyManager.shared
    private let audioCapture = AudioCapture()
    private let httpClient = GenericTranscriptionClient()
    @MainActor private var modelTask: Task<WhisperTranscriptionClient, Error>?
    @MainActor private var modelTaskName: String?
    @MainActor private var isProcessing = false
    
    private let pasteboardInjector = PasteboardInjector()
    private let keystrokeInjector = KeystrokeInjector()
    private let audioSilencer = AudioSilencer.shared
    
    private var isRecording = false
    private var audioPlayer: AVAudioPlayer?
    
    /// Audio playback only enabled with -debug-playback launch argument
    private let debugPlayback: Bool = ProcessInfo.processInfo.arguments.contains("-debug-playback")
    
    private init() {
        hotkeyManager.delegate = self
        audioCapture.delegate = self
    }
    
    public func start() {
        print("[DictationService] Starting... (debugPlayback=\(debugPlayback))")
        
        // Load embedded whisper model if provider is embedded
        Task { @MainActor in
            guard SettingsManager.shared.provider == "embedded" else { return }
            do {
                _ = try await prepareWhisperModel(SettingsManager.shared.whisperModel)
                RecordingHUDController.shared.showToast(text: "✔ Dictation ready", type: .success)
            } catch {
                showModelError(error)
            }
        }
        
        // Pre-request mic permission so first hold-to-record works immediately
        audioCapture.requestMicrophonePermission { granted in
            if granted {
                print("[DictationService] ✅ Mic permission pre-authorized")
            } else {
                print("[DictationService] ⚠️ Mic permission not granted")
            }
        }
        hotkeyManager.startMonitoring()
    }
    
    /// Share one in-flight preparation task; a changed filename loads on the next dictation.
    @MainActor private func prepareWhisperModel(_ modelName: String) async throws -> WhisperTranscriptionClient {
        if modelTaskName != modelName || modelTask == nil {
            modelTaskName = modelName
            modelTask = Task {
                let manager = WhisperModelManager.shared
                if !manager.isModelAvailable(modelName) {
                    RecordingHUDController.shared.showToast(text: "↓ Downloading model…", type: .transcribing)
                }
                let url = try await manager.downloadModel(modelName) { completed, total in
                    let message = total > 0
                        ? "↓ Model: \(completed * 100 / total)%"
                        : "↓ Model: \(completed / 1_000_000) MB"
                    RecordingHUDController.shared.showToast(text: message, type: .transcribing)
                }
                RecordingHUDController.shared.showToast(text: "Loading speech model…", type: .transcribing)
                return try await Task.detached(priority: .userInitiated) {
                    let client = WhisperTranscriptionClient(modelURL: url)
                    try client.loadModel()
                    return client
                }.value
            }
        }
        let task = modelTask!
        do {
            return try await task.value
        } catch {
            // Clear failure so the next dictation retries, including after going back online.
            if modelTaskName == modelName { modelTask = nil }
            throw error
        }
    }

    @MainActor private func showModelError(_ error: Error) {
        let message: String
        if case TranscriptionError.apiError(let detail) = error { message = detail }
        else { message = error.localizedDescription }
        print("[DictationService] Model preparation failed: \(message)")
        RecordingHUDController.shared.showToast(text: "⚠ Model unavailable", type: .error, duration: 5)
        let alert = NSAlert()
        alert.messageText = "Speech model unavailable"
        alert.informativeText = "\(message)\n\nCheck your connection and model filename in Settings. Your next dictation will retry automatically."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - HotkeyDelegate (Hold-to-record)
    
    public func dictationHotkeyPressed() {
        if hotkeyManager.isForegroundAppExcluded(exclusionList: []) {
            print("[DictationService] Foreground app excluded — ignoring hotkey")
            return
        }
        
        if !isRecording {
            print("[DictationService] 🎙️ Hold started — recording...")
            if SettingsManager.shared.silenceAudioDuringDictation {
                audioSilencer.silence()
            }
            RecordingHUDController.shared.showToast(text: "🔴 Recording...", type: .recording)
            startRecording()
        }
    }
    
    public func dictationHotkeyReleased() {
        if isRecording {
            print("[DictationService] 🛑 Hold released — stopping recording...")
            stopRecording()
            // Safety net: restore audio on release in case readyToProcessWav isn't called
            audioSilencer.restore()
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
                RecordingHUDController.shared.showToast(text: "⚠ Mic permission denied", type: .error, duration: 3.0)
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
        RecordingHUDController.shared.showToast(text: "⚠ Capture failed", type: .error, duration: 3.0)
        stopRecording()
    }
    
    public func readyToProcessWav(wavData: Data) {
        print("[DictationService] WAV ready: \(wavData.count) bytes")
        
        // Restore system audio now that capture is complete
        audioSilencer.restore()
        
        // Debug playback (only with -debug-playback launch argument)
        if debugPlayback {
            playbackAudio(wavData: wavData)
        }
        
        // Show transcribing HUD
        RecordingHUDController.shared.showToast(text: "⏳ Transcribing...", type: .transcribing)
        
        // Send to transcription API
        Task { @MainActor in
            guard !isProcessing else { return }
            isProcessing = true
            defer { isProcessing = false }
            var preparingModel = false
            do {
                let sm = SettingsManager.shared
                let config = sm.buildTranscriptionConfig()
                print("[DictationService] Using \(sm.provider) → \(config.endpoint)")

                let rawText: String
                if sm.provider == "embedded" {
                    preparingModel = true
                    let wClient = try await prepareWhisperModel(config.model)
                    preparingModel = false
                    RecordingHUDController.shared.showToast(text: "⏳ Transcribing...", type: .transcribing)
                    rawText = try await wClient.transcribe(wavData: wavData, config: config)
                } else {
                    rawText = try await self.httpClient.transcribe(wavData: wavData, config: config)
                }
                print("[DictationService] ✅ Transcription complete")
                let cleaned = TextPostProcessor.process(rawText)
                
                let success = executeInjectionLadder(text: cleaned)
                print("[DictationService] Injection success: \(success)")
                
                if AXIsProcessTrusted() {
                    RecordingHUDController.shared.showToast(text: "✔ Injected", type: .success, duration: 1.5)
                } else {
                    RecordingHUDController.shared.showToast(text: "📋 ⌘V to paste", type: .success, duration: 2.5)
                }
                
                let transcript = Transcript(text: cleaned, provider: sm.provider, model: config.model, state: success ? .success : .pending)
                TranscriptStore.shared.save(transcript)
                
            } catch {
                print("[DictationService] ❌ Transcription error: \(error)")
                if preparingModel { showModelError(error) }
                else { RecordingHUDController.shared.showToast(text: "⚠ Transcription failed", type: .error, duration: 3.0) }
                let provider = SettingsManager.shared.provider
                let transcript = Transcript(text: "", provider: provider, model: "unknown", state: .failed_transcription)
                TranscriptStore.shared.save(transcript)
            }
        }
    }
    
    // MARK: - Audio Playback (debug only)
    private func playbackAudio(wavData: Data) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            do {
                self?.audioPlayer = try AVAudioPlayer(data: wavData)
                self?.audioPlayer?.play()
                print("[DictationService] 🔊 Debug playback...")
            } catch {
                print("[DictationService] ⚠️ Playback failed: \(error.localizedDescription)")
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
