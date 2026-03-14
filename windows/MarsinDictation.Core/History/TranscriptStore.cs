using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.History;

/// <summary>
/// Stores transcript entries in memory with JSON file persistence.
/// Storage location: %LOCALAPPDATA%\MarsinDictation\transcripts.json
/// </summary>
public sealed class TranscriptStore
{
    private readonly List<TranscriptEntry> _entries = new();
    private readonly string _filePath;
    private readonly ILogger<TranscriptStore> _logger;
    private readonly object _lock = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public TranscriptStore(ILogger<TranscriptStore> logger, string? filePath = null)
    {
        _logger = logger;
        _filePath = filePath ?? GetDefaultFilePath();
    }

    /// <summary>All transcript entries, newest first.</summary>
    public IReadOnlyList<TranscriptEntry> Entries
    {
        get { lock (_lock) return _entries.AsReadOnly(); }
    }

    /// <summary>Adds a transcript entry and persists to disk.</summary>
    public void Add(TranscriptEntry entry)
    {
        lock (_lock)
        {
            _entries.Insert(0, entry);
            Save();
        }
        _logger.LogDebug("Transcript added: {Id}, state: {State}", entry.Id, entry.State);
    }

    /// <summary>
    /// Returns the most recent entry with the given state, or null if none exists.
    /// </summary>
    public TranscriptEntry? GetMostRecent(TranscriptState state)
    {
        lock (_lock)
        {
            return _entries.FirstOrDefault(e => e.State == state);
        }
    }

    /// <summary>
    /// Updates the state of an entry by ID and persists.
    /// </summary>
    public bool UpdateState(string id, TranscriptState newState)
    {
        lock (_lock)
        {
            var entry = _entries.FirstOrDefault(e => e.Id == id);
            if (entry is null) return false;

            entry.State = newState;
            Save();
            _logger.LogDebug("Transcript {Id} state changed to {State}", id, newState);
            return true;
        }
    }

    /// <summary>Removes all transcript entries and deletes the file.</summary>
    public void Clear()
    {
        lock (_lock)
        {
            _entries.Clear();
            Save();
        }
        _logger.LogInformation("All transcripts cleared");
    }

    /// <summary>Loads transcript entries from the JSON file on disk.</summary>
    public void Load()
    {
        lock (_lock)
        {
            if (!File.Exists(_filePath))
            {
                _logger.LogDebug("No transcript file found at {Path}", _filePath);
                return;
            }

            try
            {
                var json = File.ReadAllText(_filePath);
                var entries = JsonSerializer.Deserialize<List<TranscriptEntry>>(json, JsonOptions);
                if (entries is not null)
                {
                    _entries.Clear();
                    _entries.AddRange(entries);
                    _logger.LogInformation("Loaded {Count} transcript(s) from disk", _entries.Count);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to load transcripts from {Path}", _filePath);
            }
        }
    }

    private void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(_filePath);
            if (dir is not null) Directory.CreateDirectory(dir);

            var json = JsonSerializer.Serialize(_entries, JsonOptions);
            File.WriteAllText(_filePath, json);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to save transcripts to {Path}", _filePath);
        }
    }

    private static string GetDefaultFilePath()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(appData, "MarsinDictation", "transcripts.json");
    }
}
