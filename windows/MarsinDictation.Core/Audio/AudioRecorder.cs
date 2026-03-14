using Microsoft.Extensions.Logging;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace MarsinDictation.Core.Audio;

/// <summary>
/// Records audio from the default microphone using WASAPI.
/// Stores the recorded audio in memory for playback or transcription.
/// </summary>
public sealed class AudioRecorder : IDisposable
{
    private readonly ILogger<AudioRecorder> _logger;
    private WasapiCapture? _capture;
    private MemoryStream? _stream;
    private WaveFileWriter? _writer;
    private bool _disposed;

    public AudioRecorder(ILogger<AudioRecorder> logger)
    {
        _logger = logger;
    }

    /// <summary>True if currently recording.</summary>
    public bool IsRecording { get; private set; }

    /// <summary>Start recording from the default microphone.</summary>
    public void Start()
    {
        if (IsRecording)
        {
            _logger.LogWarning("Already recording, ignoring Start call");
            return;
        }

        try
        {
            _stream = new MemoryStream();
            _capture = new WasapiCapture();
            _writer = new WaveFileWriter(_stream, _capture.WaveFormat);

            _capture.DataAvailable += (_, args) =>
            {
                _writer.Write(args.Buffer, 0, args.BytesRecorded);
            };

            _capture.RecordingStopped += (_, args) =>
            {
                if (args.Exception != null)
                {
                    _logger.LogError(args.Exception, "Recording error");
                }
            };

            _capture.StartRecording();
            IsRecording = true;
            _logger.LogInformation("Recording started (format: {Format})", _capture.WaveFormat);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start recording");
            CleanupCapture();
        }
    }

    /// <summary>Stop recording and return the WAV data as a byte array.</summary>
    public byte[]? Stop()
    {
        if (!IsRecording || _capture == null || _writer == null || _stream == null)
        {
            _logger.LogWarning("Not recording, ignoring Stop call");
            return null;
        }

        try
        {
            _capture.StopRecording();
            _writer.Flush();

            var data = _stream.ToArray();
            var durationMs = (data.Length * 1000.0) / (_capture.WaveFormat.AverageBytesPerSecond);
            _logger.LogInformation("Recording stopped — {Bytes} bytes, ~{Duration:F1}s",
                data.Length, durationMs / 1000.0);

            CleanupCapture();
            return data;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to stop recording");
            CleanupCapture();
            return null;
        }
    }

    private void CleanupCapture()
    {
        IsRecording = false;
        _writer?.Dispose();
        _writer = null;
        _capture?.Dispose();
        _capture = null;
        // Don't dispose _stream — caller might still need the data
        _stream = null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        CleanupCapture();
        _disposed = true;
    }
}
