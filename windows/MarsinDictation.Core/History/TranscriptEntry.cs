using System.Text.Json.Serialization;

namespace MarsinDictation.Core.History;

/// <summary>
/// State of a transcript entry in the store.
/// </summary>
public enum TranscriptState
{
    /// <summary>Transcribed and injected successfully.</summary>
    Success,

    /// <summary>Transcription succeeded but injection failed — recoverable via Alt+Shift+Z.</summary>
    Pending,

    /// <summary>Audio captured but the transcription API returned an error.</summary>
    FailedTranscription
}

/// <summary>
/// A single transcript record. Immutable data with mutable state.
/// </summary>
public sealed class TranscriptEntry
{
    public required string Id { get; init; }
    public required DateTimeOffset CreatedAt { get; init; }
    public required string Text { get; init; }
    public required string Provider { get; init; }
    public required string Model { get; init; }

    [JsonConverter(typeof(JsonStringEnumConverter))]
    public TranscriptState State { get; set; }

    /// <summary>Creates a new transcript entry with a generated ID and current timestamp.</summary>
    public static TranscriptEntry Create(string text, string provider, string model, TranscriptState state)
    {
        return new TranscriptEntry
        {
            Id = Guid.NewGuid().ToString("N"),
            CreatedAt = DateTimeOffset.UtcNow,
            Text = text,
            Provider = provider,
            Model = model,
            State = state
        };
    }
}
