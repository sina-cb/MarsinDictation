import Foundation
import Security

/// Centralized settings manager.
/// Reads: UserDefaults (prefs) → Keychain (secrets) → env vars (dev fallback).
public class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    // MARK: - Published Properties (trigger SwiftUI updates)
    
    @Published public var provider: String {
        didSet { UserDefaults.standard.set(provider, forKey: Keys.provider) }
    }
    @Published public var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Keys.language) }
    }
    @Published public var localAIEndpoint: String {
        didSet { UserDefaults.standard.set(localAIEndpoint, forKey: Keys.localAIEndpoint) }
    }
    @Published public var localAIModel: String {
        didSet { UserDefaults.standard.set(localAIModel, forKey: Keys.localAIModel) }
    }
    @Published public var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }
    @Published public var openAIAPIKey: String {
        didSet { KeychainHelper.save(key: Keys.openAIAPIKey, value: openAIAPIKey) }
    }
    @Published public var whisperModel: String {
        didSet { UserDefaults.standard.set(whisperModel, forKey: Keys.whisperModel) }
    }
    @Published public var silenceAudioDuringDictation: Bool {
        didSet { UserDefaults.standard.set(silenceAudioDuringDictation, forKey: Keys.silenceAudio) }
    }
    @Published public var duckLevel: Double {
        didSet { UserDefaults.standard.set(duckLevel, forKey: Keys.duckLevel) }
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let provider = "transcriptionProvider"
        static let language = "language"
        static let localAIEndpoint = "localAIEndpoint"
        static let localAIModel = "localAIModel"
        static let openAIModel = "openAIModel"
        static let openAIAPIKey = "openai-api-key"
        static let whisperModel = "whisperModel"
        static let silenceAudio = "silenceAudioDuringDictation"
        static let duckLevel = "duckLevel"
        static let hasSeededFromEnv = "hasSeededFromEnv"
    }
    
    // MARK: - Defaults
    
    private enum Defaults {
        static let provider = "embedded"
        static let language = "en"
        static let localAIEndpoint = "http://localhost:3840"
        static let localAIModel = "whisper-large-turbo"
        static let openAIModel = "gpt-4o-mini-transcribe"
        static let whisperModel = "ggml-base.en.bin"
    }
    
    // MARK: - Init
    
    private init() {
        let ud = UserDefaults.standard
        
        // Load from UserDefaults → env fallback → hardcoded default
        self.provider = ud.string(forKey: Keys.provider)
            ?? ProcessInfo.processInfo.environment["MARSIN_TRANSCRIPTION_PROVIDER"]
            ?? Defaults.provider
        
        self.language = ud.string(forKey: Keys.language)
            ?? ProcessInfo.processInfo.environment["MARSIN_LANGUAGE"]
            ?? Defaults.language
        
        self.localAIEndpoint = ud.string(forKey: Keys.localAIEndpoint)
            ?? ProcessInfo.processInfo.environment["LOCALAI_ENDPOINT"]
            ?? Defaults.localAIEndpoint
        
        self.localAIModel = ud.string(forKey: Keys.localAIModel)
            ?? ProcessInfo.processInfo.environment["LOCALAI_MODEL"]
            ?? Defaults.localAIModel
        
        self.openAIModel = ud.string(forKey: Keys.openAIModel)
            ?? ProcessInfo.processInfo.environment["OPENAI_MODEL"]
            ?? Defaults.openAIModel
        
        // API key: Keychain → env fallback
        self.openAIAPIKey = KeychainHelper.load(key: Keys.openAIAPIKey)
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ""
        
        self.whisperModel = ud.string(forKey: Keys.whisperModel)
            ?? ProcessInfo.processInfo.environment["MARSIN_WHISPER_MODEL"]
            ?? Defaults.whisperModel
        
        // Silence audio during dictation (default: ON)
        if ud.object(forKey: Keys.silenceAudio) != nil {
            self.silenceAudioDuringDictation = ud.bool(forKey: Keys.silenceAudio)
        } else {
            self.silenceAudioDuringDictation = true
        }
        
        // Duck level (default: 30%)
        if ud.object(forKey: Keys.duckLevel) != nil {
            self.duckLevel = ud.double(forKey: Keys.duckLevel)
        } else {
            self.duckLevel = 0.3
        }
    }
    
    // MARK: - Seed from .env (one-time migration)
    
    public func seedFromEnvIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: Keys.hasSeededFromEnv) else { return }
        
        let env = ProcessInfo.processInfo.environment
        
        if let v = env["MARSIN_TRANSCRIPTION_PROVIDER"] { provider = v }
        if let v = env["MARSIN_LANGUAGE"] { language = v }
        if let v = env["LOCALAI_ENDPOINT"] { localAIEndpoint = v }
        if let v = env["LOCALAI_MODEL"] { localAIModel = v }
        if let v = env["OPENAI_MODEL"] { openAIModel = v }
        if let v = env["OPENAI_API_KEY"], !v.isEmpty { openAIAPIKey = v }
        if let v = env["MARSIN_WHISPER_MODEL"] { whisperModel = v }
        
        ud.set(true, forKey: Keys.hasSeededFromEnv)
        print("[SettingsManager] Seeded settings from .env")
    }
    
    // MARK: - Config Builder
    
    public func buildTranscriptionConfig() -> TranscriptionConfig {
        switch provider {
        case "openai":
            return TranscriptionConfig(
                endpoint: "https://api.openai.com/v1/audio/transcriptions",
                apiKey: openAIAPIKey.isEmpty ? nil : openAIAPIKey,
                model: openAIModel,
                language: language
            )
        case "embedded":
            // Embedded whisper.cpp — config used by WhisperTranscriptionClient
            // Endpoint is unused for in-process inference; model is the GGML filename
            return TranscriptionConfig(
                endpoint: "embedded",
                apiKey: nil,
                model: whisperModel,
                language: language
            )
        default: // "localai" and any other value
            return TranscriptionConfig(
                endpoint: "\(localAIEndpoint)/v1/audio/transcriptions",
                apiKey: nil,
                model: localAIModel,
                language: language
            )
        }
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    private static let service = "com.marsinhq.MarsinDictation"
    
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
