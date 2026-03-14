using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core;

/// <summary>
/// Orchestrates the dictation pipeline: capture → transcribe → inject.
/// Phase 0: skeleton with state machine and placeholder transitions.
/// </summary>
public sealed class DictationService
{
    private readonly ILogger<DictationService> _logger;
    private DictationState _state = DictationState.Idle;
    private readonly object _stateLock = new();

    public DictationService(ILogger<DictationService> logger)
    {
        _logger = logger;
    }

    /// <summary>Current state of the dictation pipeline.</summary>
    public DictationState State
    {
        get { lock (_stateLock) return _state; }
    }

    /// <summary>Raised when the dictation state changes.</summary>
    public event Action<DictationState>? StateChanged;

    /// <summary>
    /// Toggles dictation on/off. Called by the hotkey handler.
    /// </summary>
    public void ToggleDictation()
    {
        lock (_stateLock)
        {
            switch (_state)
            {
                case DictationState.Idle:
                    TransitionTo(DictationState.Recording);
                    _logger.LogInformation("Dictation started (recording)");
                    // Phase 1+: start WASAPI capture here
                    break;

                case DictationState.Recording:
                    TransitionTo(DictationState.Transcribing);
                    _logger.LogInformation("Dictation stopped (transcribing)");
                    // Phase 2+: stop capture, encode WAV, send to provider
                    // For now, simulate immediate return to Idle
                    TransitionTo(DictationState.Idle);
                    break;

                default:
                    _logger.LogWarning("Toggle ignored — current state: {State}", _state);
                    break;
            }
        }
    }

    /// <summary>
    /// Attempts to inject the most recent pending transcript.
    /// Called by the recovery hotkey handler.
    /// </summary>
    public void TriggerRecovery()
    {
        lock (_stateLock)
        {
            _logger.LogInformation("Recovery triggered (Alt+Shift+Z)");
            // Phase 1+: pop pending transcript from TranscriptStore, re-run injection ladder
        }
    }

    /// <summary>
    /// Resets the service to Idle. Used for error recovery.
    /// </summary>
    public void Reset()
    {
        lock (_stateLock)
        {
            _logger.LogInformation("Resetting to Idle from {State}", _state);
            TransitionTo(DictationState.Idle);
        }
    }

    private void TransitionTo(DictationState newState)
    {
        _state = newState;
        StateChanged?.Invoke(newState);
    }

    /// <summary>Valid state transitions for the dictation state machine.</summary>
    public static bool IsValidTransition(DictationState from, DictationState to)
    {
        return (from, to) switch
        {
            (DictationState.Idle, DictationState.Recording) => true,
            (DictationState.Recording, DictationState.Transcribing) => true,
            (DictationState.Transcribing, DictationState.ReadyToInject) => true,
            (DictationState.Transcribing, DictationState.Error) => true,
            (DictationState.ReadyToInject, DictationState.Idle) => true,
            (DictationState.ReadyToInject, DictationState.PendingRecovery) => true,
            (DictationState.PendingRecovery, DictationState.Idle) => true,
            (DictationState.Error, DictationState.Idle) => true,
            // Reset is always valid
            (_, DictationState.Idle) => true,
            _ => false,
        };
    }
}
