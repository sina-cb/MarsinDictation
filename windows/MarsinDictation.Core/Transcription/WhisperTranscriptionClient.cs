using Whisper.net;

namespace MarsinDictation.Core.Transcription;

/// <summary>
/// In-process transcription using whisper.cpp via Whisper.net.
/// </summary>
public sealed class WhisperTranscriptionClient : ITranscriptionClient, IDisposable
{
    private volatile WhisperProcessor? _processor;
    private WhisperFactory? _factory;
    private readonly string _modelPath;
    private readonly string _language;
    // Whisper.net/native runtime initialization is process-wide; serialize model creation too.
    private static readonly object NativeModelLock = new();
    private readonly SemaphoreSlim _inferenceGate = new(1, 1);
    private volatile bool _disposed;

    public bool IsModelLoaded => !_disposed && _processor != null;

    public WhisperTranscriptionClient(string modelPath, string language = "en")
    {
        _modelPath = modelPath;
        _language = language;
    }

    /// <summary>
    /// Load the GGML model. Call once at app startup or dynamically when transcription starts.
    /// </summary>
    public void LoadModel()
    {
        lock (NativeModelLock)
        {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_processor != null) return;
        
        if (!File.Exists(_modelPath))
            throw new FileNotFoundException($"Whisper model not found at {_modelPath}");

        _factory = WhisperFactory.FromPath(_modelPath);
        _processor = _factory.CreateBuilder()
            .WithLanguage(_language)
            .WithThreads(Math.Max(Environment.ProcessorCount / 2, 2))
            .Build();
        }
    }

    public async Task<TranscriptionResult> TranscribeAsync(byte[] wavData, CancellationToken ct = default)
    {
        await _inferenceGate.WaitAsync(ct).ConfigureAwait(false);
        // Whisper.net's own async iterator may capture its caller's context internally.
        // Enter it on the pool so synchronous UI Quit/Dispose never blocks that continuation.
        try { return await Task.Run(() => TranscribeCoreAsync(wavData, ct), ct).ConfigureAwait(false); }
        finally { _inferenceGate.Release(); }
    }

    // API work must never build an inference queue or overlap desktop dictation.
    public async Task<TranscriptionResult?> TryTranscribeAsync(byte[] wavData, CancellationToken ct = default)
    {
        if (!await _inferenceGate.WaitAsync(0, ct).ConfigureAwait(false)) return null;
        try { return await Task.Run(() => TranscribeCoreAsync(wavData, ct), ct).ConfigureAwait(false); }
        finally { _inferenceGate.Release(); }
    }

    private async Task<TranscriptionResult> TranscribeCoreAsync(byte[] wavData, CancellationToken ct)
    {
        if (_disposed) return new TranscriptionResult(false, null, "Whisper client disposed");
        // Lazy load for simplicity, though the app can explicitly call LoadModel() during startup to avoid lag
        if (_processor is null)
        {
            try
            {
                LoadModel();
            }
            catch (Exception ex)
            {
                return new TranscriptionResult(false, null, $"Failed to load Whisper model: {ex.Message}");
            }
        }

        try
        {
            // IMPORTANT: The wavData must BE 16kHz, 16-bit, Mono!
            // Luckily, App.xaml.cs calls WavDownsampler before passing it to TranscribeAsync!
            // Passing it as a memory stream directly:
            using var resampledStream = new MemoryStream(wavData);

            // Run inference
            var segments = new List<string>();
            await foreach (var segment in _processor!.ProcessAsync(resampledStream, ct).ConfigureAwait(false))
            {
                segments.Add(segment.Text);
            }

            var text = string.Join("", segments).Trim();
            if (string.IsNullOrWhiteSpace(text))
                return new TranscriptionResult(true, "[no audio]", null);

            return new TranscriptionResult(true, text, null);
        }
        catch (Exception ex)
        {
            return new TranscriptionResult(false, null, $"Whisper inference failed: {ex.Message}");
        }
    }

    public void Dispose()
    {
        _inferenceGate.Wait();
        try
        {
        lock (NativeModelLock)
        {
        if (_disposed) return;
        _disposed = true;
        _processor?.Dispose();
        _factory?.Dispose();
        _processor = null;
        _factory = null;
        }
        }
        finally { _inferenceGate.Release(); }
    }
}
