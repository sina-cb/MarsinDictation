import Foundation
import SwiftWhisper
import Metal

/// In-process transcription using whisper.cpp via SwiftWhisper.
/// Loads a GGML model file and runs inference directly in the app process.
public final class WhisperTranscriptionClient: ITranscriptionClient {
    private var whisper: Whisper?
    private let modelURL: URL
    
    /// Whether the model has been loaded and is ready for inference.
    public var isModelLoaded: Bool { whisper != nil }
    
    public init(modelURL: URL) {
        self.modelURL = modelURL
    }
    
    /// Load the GGML model into memory. Call once at app startup.
    public func loadModel() throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.apiError("Model file not found at \(modelURL.path)")
        }
        
        let params = WhisperParams(strategy: .greedy)
        params.language = .english  // Default to English — avoids auto-detect crash
        
        // Detect if Metal GPU is available; fall back to CPU on Intel/older Macs
        let hasMetalGPU = WhisperTranscriptionClient.detectMetalGPU()
        if !hasMetalGPU {
            params.no_gpu = true
            print("[WhisperClient] ⚠️ No Metal GPU detected — using CPU-only inference")
        }
        
        whisper = Whisper(fromFileURL: modelURL, withParams: params)
        print("[WhisperClient] ✅ Model loaded from \(modelURL.lastPathComponent) (GPU: \(hasMetalGPU))")
    }
    
    /// Check if a Metal-capable GPU is available on this Mac.
    private static func detectMetalGPU() -> Bool {
        #if arch(arm64)
        // Apple Silicon always has Metal
        return true
        #else
        // Intel Mac — check for Metal device
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        // Require at least macOS GPU Family 1 v4 for decent performance
        return device.supportsFamily(.common1)
        #endif
    }
    
    public func transcribe(wavData: Data, config: TranscriptionConfig) async throws -> String {
        guard let whisper = whisper else {
            throw TranscriptionError.apiError("Whisper model not loaded")
        }
        
        // Convert WAV (hardware sample rate, 16-bit PCM, mono) → Float32 at 16kHz
        let samples = try convertToWhisperFormat(wavData: wavData)
        
        guard !samples.isEmpty else {
            throw TranscriptionError.emptyResponse
        }
        
        print("[WhisperClient] Transcribing \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s at 16kHz)")
        
        // Update language if specified
        if let lang = config.language, let whisperLang = WhisperLanguage(rawValue: lang) {
            whisper.params.language = whisperLang
        }
        
        // Run inference
        let segments = try await whisper.transcribe(audioFrames: samples)
        
        let text = segments.map { $0.text }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else {
            throw TranscriptionError.emptyResponse
        }
        
        return text
    }
    
    /// Convert WAV (any sample rate, 16-bit PCM, mono) → 16kHz Float32 for whisper.cpp.
    /// Reads sample rate from WAV header and resamples via linear interpolation.
    private func convertToWhisperFormat(wavData: Data) throws -> [Float] {
        guard wavData.count > 44 else {
            throw TranscriptionError.apiError("WAV data too short (\(wavData.count) bytes)")
        }
        
        // Read sample rate from WAV header (bytes 24-27, little-endian UInt32)
        let sourceSampleRate: UInt32 = wavData.withUnsafeBytes { buf in
            buf.load(fromByteOffset: 24, as: UInt32.self)
        }
        
        let pcmData = wavData.dropFirst(44)
        
        // Convert Int16 → Float32
        let int16Samples: [Int16] = pcmData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Int16.self))
        }
        let float32Samples = int16Samples.map { Float($0) / 32768.0 }
        
        // No resampling needed if already 16kHz
        if sourceSampleRate == 16000 {
            return float32Samples
        }
        
        // Resample using linear interpolation
        let ratio = Double(sourceSampleRate) / 16000.0
        let outputCount = Int(Double(float32Samples.count) / ratio)
        
        guard outputCount > 0 else {
            throw TranscriptionError.apiError("Audio too short after resampling")
        }
        
        print("[WhisperClient] Resampling \(sourceSampleRate)Hz → 16kHz (\(float32Samples.count) → \(outputCount) samples)")
        
        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIndex = Double(i) * ratio
            let idx0 = Int(srcIndex)
            let idx1 = min(idx0 + 1, float32Samples.count - 1)
            let frac = Float(srcIndex - Double(idx0))
            output[i] = float32Samples[idx0] * (1.0 - frac) + float32Samples[idx1] * frac
        }
        
        return output
    }
}
