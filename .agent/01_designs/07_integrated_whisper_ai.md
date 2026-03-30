# Integrated Whisper — Embedded Speech-to-Text

> Design document for bundling whisper.cpp directly into the MarsinDictation binary on macOS and Windows, eliminating the need for an external transcription server.

---

## Overview

MarsinDictation currently relies on an **external process** for local transcription — either a LocalAI server or the OpenAI cloud API. This design proposes embedding the [whisper.cpp](https://github.com/ggerganov/whisper.cpp) inference engine **in-process**, so that the app ships as a single binary (plus model file) with zero external dependencies for offline speech-to-text.

---

## Motivation

| Problem with LocalAI | How Embedded Fixes It |
|-----------------------|------------------------|
| User must install, configure, and run a separate server | Nothing to install — just launch the app |
| LocalAI must be running before dictation works | Model loads on app startup, always ready |
| Port conflicts, version mismatches, Docker overhead | No network stack involved — direct function call |
| Confusing setup for non-technical users | True zero-config: download app → use |
| ~500 MB+ LocalAI install + model download | Ship only the model file (~547 MB quantized) |

> [!IMPORTANT]
> This does **not** replace the OpenAI cloud provider. Users who prefer cloud transcription (better accuracy, newer models like `gpt-4o-transcribe`) keep that option. Embedded Whisper becomes the **new default** local provider, replacing LocalAI.

---

## Architecture Change

### Before (v0 — HTTP Client)

```
┌─────────────────────┐       HTTP        ┌─────────────────────┐
│  MarsinDictation    │ ──────────────►   │  LocalAI Server     │
│  (captures audio)   │  /v1/audio/       │  (whisper.cpp)      │
│                     │  transcriptions   │                     │
└─────────────────────┘                   └─────────────────────┘
         App process                         Separate process
```

### After (v1 — In-Process)

```
┌──────────────────────────────────────────┐
│  MarsinDictation                         │
│  ┌──────────────┐   ┌─────────────────┐  │
│  │ Audio Capture │──►│ WhisperClient   │  │
│  │ (AVAudioEngine│   │ (whisper.cpp    │  │
│  │  / WASAPI)    │   │  in-process)    │  │
│  └──────────────┘   └─────────────────┘  │
│                            │              │
│                     ggml-large-v3-turbo   │
│                     -q5_0.bin (547 MB)    │
└──────────────────────────────────────────┘
               Single process
```

---

## Provider Model (Updated)

The existing `ITranscriptionClient` abstraction remains. A new implementation is added alongside the existing ones:

| Provider | Implementation | Transport | Status |
|----------|---------------|-----------|--------|
| **Embedded Whisper** *(new default)* | `WhisperTranscriptionClient` | In-process function call | **This design** |
| **OpenAI** | `GenericTranscriptionClient` / `OpenAITranscriptionClient` | HTTPS to `api.openai.com` | Existing |
| **LocalAI** *(deprecated)* | `GenericTranscriptionClient` / `OpenAITranscriptionClient` | HTTP to `localhost` | Existing, demoted |

> [!NOTE]
> LocalAI remains functional for users who have it set up, but the Settings UI defaults to `embedded` and the setup docs no longer recommend LocalAI for new users.

---

## Model Selection

### Recommended Model

| Property | Value |
|----------|-------|
| **Model** | `ggml-large-v3-turbo-q5_0` |
| **File size** | ~547 MB |
| **Parameters** | ~809M (4/5-bit quantized) |
| **Runtime RAM** | ~1–1.5 GB |
| **Speed** | ~10–15× realtime on Apple Silicon, ~5–8× on modern x86 |
| **Languages** | 99 languages (auto-detect or specify) |
| **Accuracy** | Near-parity with full-precision `large-v3-turbo` |

### Why `q5_0` Quantization?

- **Half the file size** of full-precision (547 MB vs 1.5 GB) — critical for download/distribution
- **~30% less RAM** at runtime
- **Negligible accuracy loss** — measurably indistinguishable for dictation-length audio
- **Faster inference** — less memory bandwidth pressure

### Alternative Models (User-Selectable)

| Model | File Size | RAM | Speed | Accuracy | Use Case |
|-------|-----------|-----|-------|----------|----------|
| `ggml-tiny` | 75 MB | ~200 MB | Very fast | Lower | Weak hardware, quick testing |
| `ggml-base` | 142 MB | ~350 MB | Fast | OK | Casual use, low-spec machines |
| `ggml-small` | 466 MB | ~850 MB | Medium | Good | Balanced |
| `ggml-large-v3-turbo-q5_0` | 547 MB | ~1.2 GB | Fast | **Excellent** | **Default / recommended** |
| `ggml-large-v3-turbo-q8_0` | 834 MB | ~1.8 GB | Fast | Excellent+ | When quality matters most |
| `ggml-large-v3-turbo` | 1.5 GB | ~3 GB | Fast | Best | Maximum quality, 16+ GB RAM |

> [!TIP]
> The app should allow users to select a model in Settings. The recommended default (`q5_0`) balances file size, speed, and accuracy for typical dictation workloads.

---

## macOS Implementation

### Integration Strategy: whisper.cpp via Swift Package Manager

The official `whisper.cpp` repository supports Swift Package Manager (SPM) directly. This is the cleanest integration path for Xcode projects.

#### Package Dependency

Add to `project.yml` (XcodeGen):

```yaml
packages:
  whisper:
    url: https://github.com/ggerganov/whisper.cpp
    from: "1.7.0"

targets:
  MarsinDictation:
    dependencies:
      - package: whisper
        product: whisper
```

Or alternatively, use the **SwiftWhisper** wrapper for a more ergonomic Swift API:

```yaml
packages:
  SwiftWhisper:
    url: https://github.com/exPHAT/SwiftWhisper
    branch: master

targets:
  MarsinDictation:
    dependencies:
      - package: SwiftWhisper
```

#### New File: `Core/Transcription/WhisperTranscriptionClient.swift`

```swift
import Foundation
import whisper  // or SwiftWhisper

public final class WhisperTranscriptionClient: ITranscriptionClient {
    private var context: OpaquePointer?
    private let modelPath: String
    
    public init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    /// Load model into memory. Call once at app startup.
    public func loadModel() throws {
        let params = whisper_context_default_params()
        context = whisper_init_from_file_with_params(modelPath, params)
        guard context != nil else {
            throw TranscriptionError.apiError("Failed to load Whisper model at \(modelPath)")
        }
    }
    
    public func transcribe(wavData: Data, config: TranscriptionConfig) async throws -> String {
        guard let ctx = context else {
            throw TranscriptionError.apiError("Whisper model not loaded")
        }
        
        // Convert WAV (48kHz, 16-bit PCM) → Float32 samples at 16kHz
        let samples = try convertToWhisperFormat(wavData: wavData)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.language = config.language.flatMap { 
                    ($0 as NSString).utf8String 
                }
                params.n_threads = Int32(max(ProcessInfo.processInfo.activeProcessorCount - 2, 1))
                params.no_timestamps = true
                
                let result = samples.withUnsafeBufferPointer { buffer in
                    whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
                }
                
                guard result == 0 else {
                    continuation.resume(throwing: TranscriptionError.apiError("Whisper inference failed"))
                    return
                }
                
                let nSegments = whisper_full_n_segments(ctx)
                var text = ""
                for i in 0..<nSegments {
                    if let segmentText = whisper_full_get_segment_text(ctx, i) {
                        text += String(cString: segmentText)
                    }
                }
                
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continuation.resume(throwing: TranscriptionError.emptyResponse)
                    return
                }
                
                continuation.resume(returning: trimmed)
            }
        }
    }
    
    /// Resample 48kHz 16-bit PCM WAV → 16kHz Float32 (whisper.cpp requirement)
    private func convertToWhisperFormat(wavData: Data) throws -> [Float] {
        // Skip 44-byte WAV header
        let pcmData = wavData.dropFirst(44)
        let sampleCount = pcmData.count / 2  // 16-bit = 2 bytes per sample
        
        // Convert Int16 → Float32
        let int16Samples: [Int16] = pcmData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Int16.self))
        }
        let float32Samples = int16Samples.map { Float($0) / 32768.0 }
        
        // Downsample 48kHz → 16kHz (factor of 3)
        let ratio = 3
        let outputCount = float32Samples.count / ratio
        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            output[i] = float32Samples[i * ratio]
        }
        
        return output
    }
    
    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }
}
```

#### CoreML Acceleration (Apple Silicon)

whisper.cpp supports **Core ML** for the encoder portion, offloading compute to the Apple Neural Engine (ANE). This provides significant speedups on M1/M2/M3/M4 Macs.

| Approach | Speed Boost | Complexity |
|----------|-------------|------------|
| **CPU only** | Baseline (~10× realtime) | Zero setup |
| **Metal GPU** | ~1.5–2× faster | Built-in to whisper.cpp, no extra files |
| **Core ML ANE** | ~2–3× faster | Requires separate `.mlmodelc` bundle (~equal size to GGML model) |

> [!NOTE]
> For v1, use **CPU + Metal** (automatic in whisper.cpp on Apple Silicon). Core ML ANE support is a future optimization that requires generating and bundling a separate encoder model — not worth the doubled download size for v1.

#### Model Storage (macOS)

```
~/Library/Application Support/MarsinDictation/models/
  └── ggml-large-v3-turbo-q5_0.bin    (547 MB)
```

- Model is **not** bundled inside the `.app` — downloaded on first launch or on demand
- Path is configurable in Settings for power users who manage their own models
- App checks for model on startup and shows a download prompt if missing

---

## Windows Implementation

### Integration Strategy: Whisper.net NuGet Package

[Whisper.net](https://github.com/sandrohanea/whisper.net) is a production-quality C# wrapper for whisper.cpp, distributed via NuGet with platform-specific runtime packages.

#### NuGet Packages

Add to `MarsinDictation.Core.csproj`:

```xml
<ItemGroup>
  <!-- Existing packages -->
  <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="8.0.*" />
  <PackageReference Include="NAudio" Version="2.2.*" />
  <PackageReference Include="System.Security.Cryptography.ProtectedData" Version="8.0.*" />
  
  <!-- NEW: Embedded Whisper -->
  <PackageReference Include="Whisper.net" Version="1.9.*" />
  <PackageReference Include="Whisper.net.Runtime" Version="1.9.*" />
</ItemGroup>
```

Runtime packages are modular — each provides native `whisper.cpp` binaries for specific hardware:

| Package | Hardware | Auto-Selected |
|---------|----------|---------------|
| `Whisper.net.Runtime` | CPU (AVX2) | Default fallback |
| `Whisper.net.Runtime.Cuda` | NVIDIA GPU (CUDA) | If CUDA drivers present |
| `Whisper.net.Runtime.Vulkan` | GPU (Vulkan API) | If Vulkan installed |
| `Whisper.net.Runtime.NoAvx` | Older CPUs without AVX | Manual override |

> [!TIP]
> For v1, ship with `Whisper.net.Runtime` (CPU) only. GPU acceleration can be added later as optional runtime packages. CPU inference with `large-v3-turbo-q5_0` is fast enough for dictation on modern hardware (~5–8× realtime).

#### New File: `Transcription/WhisperTranscriptionClient.cs`

```csharp
using Whisper.net;
using Whisper.net.Ggml;
using NAudio.Wave;

namespace MarsinDictation.Core.Transcription;

/// <summary>
/// In-process transcription using whisper.cpp via Whisper.net.
/// </summary>
public class WhisperTranscriptionClient : ITranscriptionClient, IDisposable
{
    private WhisperProcessor? _processor;
    private WhisperFactory? _factory;
    private readonly string _modelPath;
    private readonly string _language;

    public WhisperTranscriptionClient(string modelPath, string language = "en")
    {
        _modelPath = modelPath;
        _language = language;
    }

    /// <summary>
    /// Load the GGML model. Call once at app startup.
    /// </summary>
    public void LoadModel()
    {
        _factory = WhisperFactory.FromPath(_modelPath);
        _processor = _factory.CreateBuilder()
            .WithLanguage(_language)
            .WithNoTimestamps()
            .WithThreads(Math.Max(Environment.ProcessorCount - 2, 1))
            .Build();
    }

    public async Task<TranscriptionResult> TranscribeAsync(
        byte[] wavData, CancellationToken ct = default)
    {
        if (_processor is null)
            return new TranscriptionResult(false, null, "Whisper model not loaded");

        try
        {
            // Convert 48kHz 16-bit WAV → 16kHz (whisper.cpp requirement)
            using var inputStream = new MemoryStream(wavData);
            using var reader = new WaveFileReader(inputStream);
            
            var targetFormat = new WaveFormat(16000, 16, 1);
            using var resampler = new MediaFoundationResampler(reader, targetFormat);
            resampler.ResamplerQuality = 60;
            
            using var resampledStream = new MemoryStream();
            WaveFileWriter.WriteWavFileToStream(resampledStream, resampler);
            resampledStream.Position = 0;

            // Run inference
            var segments = new List<string>();
            await foreach (var segment in _processor.ProcessAsync(resampledStream, ct))
            {
                segments.Add(segment.Text);
            }

            var text = string.Join("", segments).Trim();
            if (string.IsNullOrWhiteSpace(text))
                return new TranscriptionResult(false, null, "No speech detected");

            return new TranscriptionResult(true, text, null);
        }
        catch (Exception ex)
        {
            return new TranscriptionResult(false, null, $"Whisper inference failed: {ex.Message}");
        }
    }

    public void Dispose()
    {
        _processor?.Dispose();
        _factory?.Dispose();
    }
}
```

#### Model Storage (Windows)

```
%LOCALAPPDATA%\MarsinDictation\models\
  └── ggml-large-v3-turbo-q5_0.bin    (547 MB)
```

- Same download-on-first-launch strategy as macOS
- App checks for model on startup, shows download dialog if missing

---

## Model Download System

The model file is **not** bundled with the application binary. It is downloaded on first launch (or when the user selects a different model).

### Download Flow

```
┌──────────────────────────────────────────────────────────────┐
│  1. App launches                                             │
│  2. Check model directory for configured model file          │
│     → Found: Load model, ready to transcribe                 │
│     → Not found: Continue to step 3                          │
│  3. Show modal dialog:                                       │
│     "MarsinDictation needs to download a speech model         │
│      (~547 MB) for offline transcription.                     │
│      [Download Now]  [Use Cloud Instead]  [Browse...]"        │
│  4. If Download Now:                                         │
│     a. Download from Hugging Face (HTTPS, resumable)         │
│     b. Show progress bar with MB downloaded / total          │
│     c. Verify SHA256 checksum after download                 │
│     d. Load model, ready to transcribe                       │
│  5. If Use Cloud Instead:                                    │
│     a. Switch provider to OpenAI                             │
│     b. Prompt for API key if not configured                  │
│  6. If Browse:                                               │
│     a. User selects an existing .bin model file              │
│     b. Load model, ready to transcribe                       │
└──────────────────────────────────────────────────────────────┘
```

### Download Source

```
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

- Hugging Face CDN — fast, reliable, no auth required
- Support HTTP `Range` headers for **resumable downloads**
- Verify integrity with SHA256 checksum (published alongside the model)

---

## Audio Format Conversion

whisper.cpp requires audio in a specific format that differs from what MarsinDictation currently captures:

| Property | Current Capture | whisper.cpp Requirement |
|----------|----------------|------------------------|
| **Sample rate** | 48,000 Hz | **16,000 Hz** |
| **Channels** | Mono | Mono |
| **Bit depth** | 16-bit PCM (Int16) | **32-bit Float** |
| **Container** | WAV | Raw PCM samples |

### Conversion Pipeline

```
AVAudioEngine / WASAPI (48kHz, 16-bit, mono WAV)
    │
    ▼
Resample 48kHz → 16kHz
    │
    ▼
Convert Int16 → Float32 (divide by 32768.0)
    │
    ▼
whisper_full(ctx, params, float32_samples, n_samples)
```

- **macOS**: Use `vDSP` (Accelerate framework) for fast sample rate conversion, or simple decimation (48/16 = 3, take every 3rd sample) for dictation-quality audio
- **Windows**: Use `NAudio.MediaFoundationResampler` (already a project dependency) for high-quality resampling

---

## Configuration Changes

### Settings UI Updates

Add a new provider option and model selector:

| Setting | Default | Type |
|---------|---------|------|
| Transcription provider | `embedded` | Enum: `embedded` / `openai` / `localai` |
| Whisper model | `ggml-large-v3-turbo-q5_0` | Dropdown (installed models) |
| Model directory | *(platform default)* | Path (advanced) |

### Environment Variables

```bash
MARSIN_TRANSCRIPTION_PROVIDER=embedded    # NEW default (was: localai)
MARSIN_WHISPER_MODEL=ggml-large-v3-turbo-q5_0.bin
MARSIN_WHISPER_MODEL_DIR=~/Library/Application Support/MarsinDictation/models
MARSIN_LANGUAGE=en
```

### Priority Order (Unchanged Pattern)

1. **In-app Settings** (UserDefaults / app config) — takes priority
2. **Environment variables** (`.env` file) — fallback for development
3. **Hardcoded defaults** — `embedded`, `ggml-large-v3-turbo-q5_0`, `en`

---

## Module Structure Changes

### macOS — New/Modified Files

```
mac/Core/Transcription/
├── ITranscriptionClient.swift              # Unchanged
├── GenericTranscriptionClient.swift        # Unchanged (used for OpenAI/LocalAI)
└── WhisperTranscriptionClient.swift        # NEW — in-process whisper.cpp

mac/Core/
├── DictationService.swift                  # MODIFIED — add embedded provider routing
└── SettingsManager.swift                   # MODIFIED — add embedded provider + model settings

mac/MarsinDictationApp/
└── ModelDownloader.swift                   # NEW — download manager with progress UI
```

### Windows — New/Modified Files

```
windows/MarsinDictation.Core/Transcription/
├── ITranscriptionClient.cs                 # Unchanged
├── OpenAITranscriptionClient.cs            # Unchanged
└── WhisperTranscriptionClient.cs           # NEW — in-process Whisper.net

windows/MarsinDictation.Core/
├── DictationService.cs                     # MODIFIED — add embedded provider routing
└── Settings/                               # MODIFIED — add embedded provider + model settings

windows/MarsinDictation.App/
└── ModelDownloader.cs                      # NEW — download manager with progress UI
```

---

## Performance Expectations

### Transcription Latency (10-second audio clip)

| Platform | Hardware | Model | Expected Latency |
|----------|----------|-------|-----------------|
| macOS | M1/M2/M3 (Apple Silicon) | `q5_0` | ~0.7–1.0 sec |
| macOS | Intel Mac (i7/i9) | `q5_0` | ~1.5–2.5 sec |
| Windows | Modern x86_64 (i7/Ryzen 7) | `q5_0` | ~1.2–2.0 sec |
| Windows | NVIDIA GPU (CUDA runtime) | `q5_0` | ~0.5–0.8 sec |

### Model Load Time (One-Time, on App Startup)

| Platform | Model | Expected Load Time |
|----------|-------|--------------------|
| Apple Silicon | `q5_0` (547 MB) | ~1–2 sec |
| x86_64 CPU | `q5_0` (547 MB) | ~2–4 sec |

> [!NOTE]
> Model load happens **once** at app startup and stays in memory. Subsequent transcriptions use the already-loaded model. The app should show a brief loading indicator during initial model load.

---

## App Size Impact

| Component | macOS | Windows |
|-----------|-------|---------|
| **App binary (before)** | ~5 MB | ~8 MB |
| **whisper.cpp library** | +2–3 MB (linked via SPM) | +3–5 MB (Whisper.net + runtime DLLs) |
| **App binary (after)** | ~7–8 MB | ~11–13 MB |
| **Model file (separate download)** | 547 MB | 547 MB |
| **Total on disk** | ~555 MB | ~560 MB |

> [!WARNING]
> The model file is large. It must **not** be bundled inside the app binary or installer. It should be downloaded separately on first launch with clear UX indicating the download size and progress.

---

## Migration Path

### For Existing LocalAI Users

1. On update, the default provider changes from `localai` to `embedded`
2. If no model file exists, the app prompts to download one
3. Users who decline can manually switch back to `localai` or `openai` in Settings
4. LocalAI configuration remains functional — no breaking changes

### For New Users

1. Install app → launch
2. One-time model download prompt (~547 MB)
3. Ready to dictate — no server setup, no API keys, no configuration

---

## Failure Modes

| Failure | User Experience |
|---------|----------------|
| Model file missing | Dialog: "Download speech model?" with Download / Browse / Cloud options |
| Model file corrupted | Re-download prompt with checksum verification |
| Model download fails (no internet) | Offer to switch to OpenAI, or retry later |
| Model download interrupted | Resume from where it left off (HTTP Range) |
| Insufficient RAM for model | Fall back to smaller model suggestion: "Try `ggml-small` (466 MB, ~850 MB RAM)" |
| Inference fails on audio | Same error UX as current: HUD shows "⚠ Transcription failed" |
| Extremely long audio (>25 MB WAV) | AudioGuard still enforces the limit (unchanged from v0) |

---

## Security & Privacy

| Concern | Mitigation |
|---------|------------|
| **Audio privacy** | Audio never leaves the device — processed entirely in-memory |
| **Model integrity** | SHA256 checksum verification after download |
| **Download source** | Hugging Face CDN over HTTPS — no custom infrastructure |
| **No telemetry** | No usage data sent anywhere — fully offline after model download |

---

## Open Questions

> [!IMPORTANT]
> **Model bundling strategy for distribution**: Should we offer a "full installer" that includes the model (~550 MB) alongside a "light installer" (~10 MB) that downloads the model on first launch? The full installer is better for air-gapped environments but significantly increases download/distribution size.

> [!IMPORTANT]
> **SwiftWhisper vs raw whisper.cpp on macOS**: SwiftWhisper provides a cleaner Swift API but adds a third-party dependency. Raw whisper.cpp via SPM is more direct but requires manual C interop (bridging header, memory management). Recommendation: start with raw whisper.cpp SPM since the official repo has Swift/SwiftUI examples and avoids a third-party dependency.

> [!IMPORTANT]
> **Model auto-update**: Should the app check for newer/better quantized models and offer upgrades? This adds complexity but ensures users benefit from future model improvements (e.g., `large-v4`).

---

## Acceptance Criteria

- [ ] Embedded Whisper transcription works end-to-end on macOS (Apple Silicon)
- [ ] Embedded Whisper transcription works end-to-end on macOS (Intel)
- [ ] Embedded Whisper transcription works end-to-end on Windows (x86_64)
- [ ] Model download with progress UI and resumable downloads
- [ ] SHA256 checksum verification after model download
- [ ] Audio resampling from 48kHz → 16kHz works correctly
- [ ] Settings UI allows switching between `embedded` / `openai` / `localai`
- [ ] Settings UI allows selecting installed model
- [ ] Model loads on app startup with loading indicator
- [ ] Graceful fallback when model is missing (download prompt)
- [ ] No regression in existing OpenAI / LocalAI provider paths
- [ ] Transcription latency < 2 sec for 10-second audio on Apple Silicon
- [ ] Memory usage stays under 2 GB with `q5_0` model loaded

---

## Future Considerations

- **Core ML ANE acceleration** (macOS): Bundle a `.mlmodelc` encoder for 2–3× speedup on Apple Silicon Neural Engine
- **CUDA / Vulkan runtime** (Windows): Ship optional GPU-accelerated runtime packages for NVIDIA/AMD users
- **Streaming partial results**: whisper.cpp supports segment callbacks — could show partial transcription while still processing
- **Voice Activity Detection (VAD)**: Use whisper.cpp's built-in VAD to skip silence, reducing processing time for long recordings
- **Model manager UI**: Browse, download, and delete models from within the app
- **Smaller default model**: If `ggml-small` accuracy proves sufficient for dictation, consider it as the default to reduce download size to ~466 MB
