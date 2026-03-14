namespace MarsinDictation.Core.Transcription;

/// <summary>
/// Result of a transcription attempt.
/// </summary>
/// <param name="Success">True if transcription succeeded.</param>
/// <param name="Text">Transcribed text (null on failure).</param>
/// <param name="Error">Error message (null on success).</param>
public record TranscriptionResult(bool Success, string? Text, string? Error);

/// <summary>
/// Abstraction for audio-to-text transcription providers.
/// Both OpenAI and LocalAI implement the same /v1/audio/transcriptions endpoint.
/// </summary>
public interface ITranscriptionClient
{
    /// <summary>Transcribes WAV audio data to text.</summary>
    Task<TranscriptionResult> TranscribeAsync(byte[] wavData, CancellationToken ct = default);
}
