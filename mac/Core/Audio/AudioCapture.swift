import Foundation
import AVFoundation

public protocol AudioCaptureDelegate: AnyObject {
    func captureFailed(error: Error)
    func readyToProcessWav(wavData: Data)
}

public enum AudioCaptureError: Error, LocalizedError {
    case noInputDevice
    case micPermissionDenied
    case engineStartFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone found. Check your audio settings."
        case .micPermissionDenied:
            return "Microphone permission denied."
        case .engineStartFailed(let err):
            return "Audio engine failed to start: \(err.localizedDescription)"
        }
    }
}

public class AudioCapture: AudioGuardDelegate {
    public weak var delegate: AudioCaptureDelegate?
    
    private var engine: AVAudioEngine?
    private var accumulatedData = Data()
    
    // Audio format constants
    private let recordingChannels: AVAudioChannelCount = 1
    private let recordingBitsPerSample: UInt32 = 16
    /// Actual sample rate from the hardware (set when capture starts)
    private var actualSampleRate: Double = 48000.0
    
    private let audioGuard = AudioGuard()
    
    public init() {
        audioGuard.delegate = self
    }
    
    public func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[AudioCapture] Mic permission status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("[AudioCapture] Mic permission response: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            print("[AudioCapture] ⚠️ Mic permission denied/restricted")
            completion(false)
        }
    }
    
    public func startCapture() {
        print("[AudioCapture] Starting capture...")
        accumulatedData.removeAll()
        audioGuard.reset()
        
        let newEngine = AVAudioEngine()
        
        // Accessing inputNode triggers CoreAudio initialization
        // The -10877/AddInstanceForFactory warnings are harmless stderr noise
        let inputNode = newEngine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        actualSampleRate = hwFormat.sampleRate
        
        print("[AudioCapture] Hardware format: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch, \(hwFormat.commonFormat.rawValue)")
        
        guard hwFormat.channelCount > 0 else {
            print("[AudioCapture] ❌ No input channels — no mic available")
            delegate?.captureFailed(error: AudioCaptureError.noInputDevice)
            return
        }
        
        print("[AudioCapture] Installing tap with hardware format...")
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            
            // Downmix to mono and convert float32 → int16
            var int16Data = Data(capacity: frameCount * 2)
            for frame in 0..<frameCount {
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample += channelData[ch][frame]
                }
                sample /= Float(channelCount)
                
                let clamped = max(-1.0, min(1.0, sample))
                var int16 = Int16(clamped * Float(Int16.max))
                int16Data.append(Data(bytes: &int16, count: 2))
            }
            
            self.accumulatedData.append(int16Data)
            self.audioGuard.addBytes(int16Data.count)
        }
        
        newEngine.prepare()
        do {
            try newEngine.start()
            self.engine = newEngine
            print("[AudioCapture] ✅ Engine started — recording!")
        } catch {
            print("[AudioCapture] ❌ Engine failed to start: \(error)")
            inputNode.removeTap(onBus: 0)
            delegate?.captureFailed(error: AudioCaptureError.engineStartFailed(error))
        }
    }
    
    public func stopCapture() {
        guard let engine = engine, engine.isRunning else {
            print("[AudioCapture] stopCapture called but engine not running")
            return
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        
        print("[AudioCapture] Stopped. Accumulated \(accumulatedData.count) bytes of PCM data")
        
        guard !accumulatedData.isEmpty else {
            print("[AudioCapture] ⚠️ No audio data captured")
            return
        }
        
        // Build WAV header for mono Int16 PCM at the actual hardware sample rate
        let sampleRate = UInt32(actualSampleRate)
        let numChannels: UInt16 = UInt16(recordingChannels)
        let bitsPerSample: UInt16 = UInt16(recordingBitsPerSample)
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        
        let dataSize = UInt32(accumulatedData.count)
        let chunkSize = 36 + dataSize
        
        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(withUnsafeBytes(of: chunkSize) { Data($0) })
        wav.append(contentsOf: "WAVE".utf8)
        
        let fmtChunkSize: UInt32 = 16
        let audioFormat: UInt16 = 1  // PCM integer
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(withUnsafeBytes(of: fmtChunkSize) { Data($0) })
        wav.append(withUnsafeBytes(of: audioFormat) { Data($0) })
        wav.append(withUnsafeBytes(of: numChannels) { Data($0) })
        wav.append(withUnsafeBytes(of: sampleRate) { Data($0) })
        wav.append(withUnsafeBytes(of: byteRate) { Data($0) })
        wav.append(withUnsafeBytes(of: blockAlign) { Data($0) })
        wav.append(withUnsafeBytes(of: bitsPerSample) { Data($0) })
        
        wav.append(contentsOf: "data".utf8)
        wav.append(withUnsafeBytes(of: dataSize) { Data($0) })
        wav.append(accumulatedData)
        
        print("[AudioCapture] ✅ WAV built: \(wav.count) bytes total")
        delegate?.readyToProcessWav(wavData: wav)
        accumulatedData.removeAll()
    }
    
    public func audioLimitReached() {
        DispatchQueue.main.async { [weak self] in
            self?.stopCapture()
        }
    }
}
