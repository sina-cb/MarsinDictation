import Foundation
import whisper_cpp
import Metal

/// In-process transcription using the pinned whisper.cpp bundled by SwiftWhisper.
/// Loads a GGML model file and runs inference directly in the app process.
public final class WhisperTranscriptionClient: ITranscriptionClient {
    private var context: OpaquePointer?
    #if DEBUG
    internal var beforeNativeLoad: (() -> Void)?
    #endif
    private let stateLock = NSLock()
    private static let loadLock = NSLock()
    private let inferenceGate = DispatchSemaphore(value: 1)
    private static let poolLock = NSLock()
    private final class WeakClient { weak var value: WhisperTranscriptionClient?; init(_ value: WhisperTranscriptionClient) { self.value = value } }
    private static var pool: [URL: WeakClient] = [:]

    public static func shared(modelURL: URL) -> WhisperTranscriptionClient {
        poolLock.lock(); defer { poolLock.unlock() }
        let key = modelURL.standardizedFileURL
        pool = pool.filter { $0.value.value != nil }
        if let client = pool[key]?.value { return client }
        let client = WhisperTranscriptionClient(modelURL: key)
        pool[key] = WeakClient(client)
        return client
    }
    private let modelURL: URL
    
    /// Whether the model has been loaded and is ready for inference.
    public var isModelLoaded: Bool { stateLock.lock(); defer { stateLock.unlock() }; return context != nil }
    
    internal var isInferenceBusy: Bool {
        if inferenceGate.wait(timeout: .now()) == .success { inferenceGate.signal(); return false }
        return true
    }

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }
    /// Load the GGML model into memory. Call once at app startup.
    public func loadModel() throws {
        Self.loadLock.lock(); defer { Self.loadLock.unlock() }
        if isModelLoaded { return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.apiError("Model file not found at \(modelURL.path)")
        }
        
        try validateNativeMetadataPrefix()

        // Detect if Metal GPU is available; fall back to CPU on Intel/older Macs
        let hasMetalGPU = MTLCreateSystemDefaultDevice() != nil
        if !hasMetalGPU {
            // Tell whisper.cpp's ggml to skip Metal acceleration
            setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)
            print("[WhisperClient] ⚠️ No Metal GPU detected — using CPU-only inference")
        }
        
        // SwiftWhisper's nonfailable initializer traps on a null native context.
        // Own the checked native result directly so unsupported/corrupt models remain recoverable.
        #if DEBUG
        beforeNativeLoad?()
        #endif
        guard let loaded = modelURL.path.withCString({ whisper_init_from_file($0) }) else {
            throw TranscriptionError.apiError("Embedded speech model could not load")
        }
        stateLock.lock(); context = loaded; stateLock.unlock()
        print("[WhisperClient] ✅ Model loaded from \(modelURL.lastPathComponent) (GPU: \(hasMetalGPU))")
    }
    
    /// Reject truncated GGML metadata before the legacy native loader can assert.
    /// This is a bounded prefix check, not a guarantee for arbitrary corrupt tensor payloads.
    private func validateNativeMetadataPrefix() throws {
        let file = try FileHandle(forReadingFrom: modelURL)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        try file.seek(toOffset: 0)
        guard let header = try file.read(upToCount: 56), header.count == 56 else {
            throw TranscriptionError.apiError("Embedded speech model metadata is truncated")
        }
        let bytes = [UInt8](header)
        func uint32(_ offset: Int) -> UInt64 {
            (0..<4).reduce(0) { $0 | UInt64(bytes[offset + $1]) << (8 * $1) }
        }
        // whisper.cpp's pinned GGML format has a 48-byte header followed by mel dimensions.
        guard Array(bytes.prefix(4)) == [0x6c, 0x6d, 0x67, 0x67],
              uint32(40) == 80, [0, 1, 2, 3, 7, 8, 9].contains(uint32(44) % 1000), uint32(48) == 80, uint32(52) == 201,
              size >= 56 + 80 * 201 * 4 + 4 else {
            throw TranscriptionError.apiError("Embedded speech model metadata is invalid or truncated")
        }
    }

    private func acquireInference() -> Bool { inferenceGate.wait(timeout: .now()) == .success }

    public func transcribe(wavData: Data, config: TranscriptionConfig) async throws -> String {
        while !acquireInference() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        defer { inferenceGate.signal() }
        return try await transcribeLocked(wavData: wavData, config: config)
    }

    /// API admission never queues behind hotkey inference. The gate remains held until native inference ends.
    public func tryTranscribe(wavData: Data, config: TranscriptionConfig) async throws -> String? {
        guard acquireInference() else { return nil }
        defer { inferenceGate.signal() }
        return try await transcribeLocked(wavData: wavData, config: config)
    }

    deinit { if let context = context { whisper_free(context) } }

    private func loadedContext() -> OpaquePointer? {
        stateLock.lock(); defer { stateLock.unlock() }; return context
    }

    /// The callback and cancellation handler share only this locked flag, not native mutable state.
    private final class CancellationFlag {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    private func transcribeLocked(wavData: Data, config: TranscriptionConfig) async throws -> String {
        guard let context = loadedContext() else {
            throw TranscriptionError.apiError("Whisper model not loaded")
        }
        let samples = try convertToWhisperFormat(wavData: wavData)
        guard !samples.isEmpty else { throw TranscriptionError.emptyResponse }
        let configuredLanguage = config.language ?? "en"
        let language = configuredLanguage.withCString { whisper_lang_id($0) } >= 0 ? configuredLanguage : "en"
        let cancellation = CancellationFlag()
        try Task.checkCancellation()
        let text: String = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    // Keep self/context, samples, callback token and C language string alive until native return.
                    _ = self
                    let result: Result<String, Error> = Result {
                        if cancellation.isCancelled { throw CancellationError() }
                        let token = Unmanaged.passRetained(cancellation)
                        defer { token.release() }
                        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                        params.print_realtime = false; params.print_progress = false
                        params.print_timestamps = false; params.print_special = false
                        params.encoder_begin_callback_user_data = token.toOpaque()
                        params.encoder_begin_callback = { _, _, userData in
                            guard let userData = userData else { return false }
                            return !Unmanaged<CancellationFlag>.fromOpaque(userData).takeUnretainedValue().isCancelled
                        }
                        let status = language.withCString { pointer in
                            params.language = pointer
                            return samples.withUnsafeBufferPointer { audio in
                                whisper_full(context, params, audio.baseAddress, Int32(audio.count))
                            }
                        }
                        if cancellation.isCancelled { throw CancellationError() }
                        guard status == 0 else { throw TranscriptionError.apiError("Embedded inference failed") }
                        var segments: [String] = []
                        for index in 0..<whisper_full_n_segments(context) {
                            if let segment = whisper_full_get_segment_text(context, index) { segments.append(String(cString: segment)) }
                        }
                        let text = segments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { throw TranscriptionError.emptyResponse }
                        return text
                    }
                    // Native return and callback-token cleanup precede gate release by the awaiting caller.
                    continuation.resume(with: result)
                }
            }
        }, onCancel: { cancellation.cancel() })
        try Task.checkCancellation()
        return text
    }

    /// Convert WAV (any sample rate, 16-bit PCM, mono) → 16kHz Float32 for whisper.cpp.
    /// Reads sample rate from WAV header and resamples via linear interpolation.
    private func convertToWhisperFormat(wavData: Data) throws -> [Float] {
        guard wavData.count > 44 else {
            throw TranscriptionError.apiError("WAV data too short (\(wavData.count) bytes)")
        }
        
        // Read sample rate from WAV header (bytes 24-27, little-endian UInt32)
        let sourceSampleRate = (0..<4).reduce(UInt32(0)) { $0 | UInt32(wavData[24 + $1]) << ($1 * 8) }
        guard sourceSampleRate > 0 else { throw TranscriptionError.invalidEncoding }
        
        let pcmData = wavData.dropFirst(44)
        
        // Convert Int16 → Float32
        let pcm = [UInt8](pcmData)
        guard pcm.count % 2 == 0 else { throw TranscriptionError.invalidEncoding }
        let float32Samples = stride(from: 0, to: pcm.count, by: 2).map { offset in
            Float(Int16(bitPattern: UInt16(pcm[offset]) | UInt16(pcm[offset + 1]) << 8)) / 32768.0
        }
        
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
