namespace MarsinDictation.Core;

/// <summary>
/// Represents the current state of the dictation service.
/// Transitions: Idle → Recording → Transcribing → ReadyToInject → Idle
///                                              → PendingRecovery → Idle
///                                              → Error → Idle
/// </summary>
public enum DictationState
{
    /// <summary>Waiting for hotkey activation.</summary>
    Idle,

    /// <summary>WASAPI capture active, overlay visible.</summary>
    Recording,

    /// <summary>Audio sent to provider, awaiting response.</summary>
    Transcribing,

    /// <summary>Text received, injection ladder executing.</summary>
    ReadyToInject,

    /// <summary>Injection failed, transcript stored, awaiting Alt+Shift+Z.</summary>
    PendingRecovery,

    /// <summary>Transient failure (no mic, API unreachable). Auto-returns to Idle.</summary>
    Error
}
