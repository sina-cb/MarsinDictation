import Foundation

/// Manages the Whisper GGML model file location and download.
public class WhisperModelManager {
    public static let shared = WhisperModelManager()
    
    /// Base URL for downloading GGML models from Hugging Face
    private let huggingFaceBaseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    
    /// Directory where models are stored
    public var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MarsinDictation/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private init() {}
    
    /// Full path to the model file — checks bundle Resources first, then Application Support
    public func modelURL(for modelName: String) -> URL {
        // Check if model is bundled in app Resources
        if let bundledURL = Bundle.main.url(forResource: (modelName as NSString).deletingPathExtension,
                                            withExtension: (modelName as NSString).pathExtension) {
            return bundledURL
        }
        return modelsDirectory.appendingPathComponent(modelName)
    }
    
    /// Check if a model file exists (in bundle or Application Support)
    public func isModelAvailable(_ modelName: String) -> Bool {
        // Check bundle first
        if Bundle.main.url(forResource: (modelName as NSString).deletingPathExtension,
                           withExtension: (modelName as NSString).pathExtension) != nil {
            return true
        }
        return FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(modelName).path)
    }
    
    /// Download a model file from Hugging Face with progress reporting.
    /// - Parameters:
    ///   - modelName: The GGML model filename (e.g. "ggml-large-v3-turbo-q5_0.bin")
    ///   - progress: Called with (bytesDownloaded, totalBytes) during download
    /// - Returns: Local URL of the downloaded model
    public func downloadModel(
        _ modelName: String,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        let remoteURL = URL(string: "\(huggingFaceBaseURL)/\(modelName)")!
        let localURL = modelURL(for: modelName)
        
        // If already exists, return immediately
        if FileManager.default.fileExists(atPath: localURL.path) {
            print("[WhisperModelManager] Model already exists at \(localURL.path)")
            return localURL
        }
        
        print("[WhisperModelManager] Downloading \(modelName) from \(remoteURL)...")
        
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL, delegate: nil)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TranscriptionError.apiError("Model download failed with HTTP \(statusCode)")
        }
        
        // Move to final location
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0
        print("[WhisperModelManager] ✅ Model downloaded: \(localURL.lastPathComponent) (\(fileSize / 1_000_000) MB)")
        
        return localURL
    }
}
