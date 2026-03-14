using Microsoft.Extensions.Logging;
using NAudio.Wave;

namespace MarsinDictation.Core.Audio;

/// <summary>
/// Plays back WAV audio from a byte array.
/// Used for the test playback mode (echo recorded audio).
/// </summary>
public sealed class AudioPlayer : IDisposable
{
    private readonly ILogger<AudioPlayer> _logger;
    private WaveOutEvent? _player;
    private bool _disposed;

    public AudioPlayer(ILogger<AudioPlayer> logger)
    {
        _logger = logger;
    }

    /// <summary>Plays the given WAV data through the default output device.</summary>
    public void Play(byte[] wavData, Action? onComplete = null)
    {
        try
        {
            var stream = new MemoryStream(wavData);
            var reader = new WaveFileReader(stream);

            _player?.Dispose();
            _player = new WaveOutEvent();
            _player.Init(reader);

            _player.PlaybackStopped += (_, _) =>
            {
                reader.Dispose();
                stream.Dispose();
                _logger.LogInformation("Playback completed");
                onComplete?.Invoke();
            };

            _player.Play();
            _logger.LogInformation("Playing back audio ({Bytes} bytes)", wavData.Length);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Playback failed");
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _player?.Dispose();
        _disposed = true;
    }
}
