using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.History;

/// <summary>
/// Stores transcript entries using sharded JSONL files (one per month).
/// Storage location: %LOCALAPPDATA%\MarsinDictation\transcripts\2026-03.jsonl
/// Each line is a self-contained JSON object — append-only for writes, merge for reads.
/// </summary>
public sealed class TranscriptStore
{
    private readonly List<TranscriptEntry> _entries = new();
    private readonly string _directory;
    private readonly ILogger<TranscriptStore> _logger;
    private readonly object _lock = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public TranscriptStore(ILogger<TranscriptStore> logger, string? directory = null)
    {
        _logger = logger;
        _directory = directory ?? GetDefaultDirectory();
    }

    /// <summary>The directory where JSONL shard files are stored.</summary>
    public string Directory => _directory;

    /// <summary>All transcript entries, newest first.</summary>
    public IReadOnlyList<TranscriptEntry> Entries
    {
        get { lock (_lock) return _entries.AsReadOnly(); }
    }

    /// <summary>Adds a transcript entry — appends to the current month's JSONL shard.</summary>
    public void Add(TranscriptEntry entry)
    {
        lock (_lock)
        {
            _entries.Insert(0, entry);
            AppendToShard(entry);
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
    /// Updates the state of an entry by ID and rewrites its shard.
    /// </summary>
    public bool UpdateState(string id, TranscriptState newState)
    {
        lock (_lock)
        {
            var entry = _entries.FirstOrDefault(e => e.Id == id);
            if (entry is null) return false;

            entry.State = newState;
            RewriteShard(entry.CreatedAt);
            _logger.LogDebug("Transcript {Id} state changed to {State}", id, newState);
            return true;
        }
    }

    /// <summary>Removes all transcript entries and deletes all shard files.</summary>
    public void Clear()
    {
        lock (_lock)
        {
            _entries.Clear();

            if (System.IO.Directory.Exists(_directory))
            {
                foreach (var file in System.IO.Directory.GetFiles(_directory, "*.jsonl"))
                {
                    try { File.Delete(file); } catch { /* best effort */ }
                }
            }
        }
        _logger.LogInformation("All transcripts cleared");
    }

    /// <summary>Loads transcript entries from all JSONL shard files.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _entries.Clear();

            // Migrate legacy single-file format if it exists
            MigrateLegacy();

            if (!System.IO.Directory.Exists(_directory))
            {
                _logger.LogDebug("No transcript directory found at {Path}", _directory);
                return;
            }

            var files = System.IO.Directory.GetFiles(_directory, "*.jsonl")
                .OrderByDescending(f => f); // newest shard first

            int total = 0;
            foreach (var file in files)
            {
                try
                {
                    foreach (var line in File.ReadAllLines(file))
                    {
                        if (string.IsNullOrWhiteSpace(line)) continue;
                        var entry = JsonSerializer.Deserialize<TranscriptEntry>(line, JsonOptions);
                        if (entry is not null)
                        {
                            _entries.Add(entry);
                            total++;
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to load shard {File}", file);
                }
            }

            // Sort newest first across all shards
            _entries.Sort((a, b) => b.CreatedAt.CompareTo(a.CreatedAt));

            if (total > 0)
                _logger.LogInformation("Loaded {Count} transcript(s) from {Shards} shard(s)",
                    total, files.Count());
            else
                _logger.LogDebug("No transcripts found");
        }
    }

    // ── Private helpers ─────────────────────────────────────────

    private void AppendToShard(TranscriptEntry entry)
    {
        try
        {
            System.IO.Directory.CreateDirectory(_directory);
            var shardPath = GetShardPath(entry.CreatedAt);
            var line = JsonSerializer.Serialize(entry, JsonOptions);
            File.AppendAllText(shardPath, line + "\n");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to append transcript to shard");
        }
    }

    private void RewriteShard(DateTimeOffset timestamp)
    {
        try
        {
            var shardPath = GetShardPath(timestamp);
            var shardEntries = _entries
                .Where(e => GetShardKey(e.CreatedAt) == GetShardKey(timestamp))
                .OrderByDescending(e => e.CreatedAt);

            var lines = shardEntries.Select(e => JsonSerializer.Serialize(e, JsonOptions));
            File.WriteAllText(shardPath, string.Join("\n", lines) + "\n");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to rewrite shard");
        }
    }

    private string GetShardPath(DateTimeOffset timestamp)
    {
        return Path.Combine(_directory, $"{GetShardKey(timestamp)}.jsonl");
    }

    private static string GetShardKey(DateTimeOffset timestamp)
    {
        return timestamp.ToString("yyyy-MM");
    }

    private void MigrateLegacy()
    {
        // Check for old single-file format: transcripts.json in parent directory
        var parentDir = Path.GetDirectoryName(_directory);
        if (parentDir is null) return;

        var legacyPath = Path.Combine(parentDir, "transcripts.json");
        if (!File.Exists(legacyPath)) return;

        _logger.LogInformation("Migrating legacy transcripts.json → JSONL shards");
        try
        {
            var json = File.ReadAllText(legacyPath);
            var legacyOpts = new JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            };
            var entries = JsonSerializer.Deserialize<List<TranscriptEntry>>(json, legacyOpts);
            if (entries is not null && entries.Count > 0)
            {
                System.IO.Directory.CreateDirectory(_directory);

                // Group by month and write shards
                var groups = entries.GroupBy(e => GetShardKey(e.CreatedAt));
                foreach (var group in groups)
                {
                    var shardPath = Path.Combine(_directory, $"{group.Key}.jsonl");
                    var lines = group
                        .OrderByDescending(e => e.CreatedAt)
                        .Select(e => JsonSerializer.Serialize(e, JsonOptions));
                    File.WriteAllText(shardPath, string.Join("\n", lines) + "\n");
                }

                _logger.LogInformation("Migrated {Count} transcript(s) to JSONL shards", entries.Count);
            }

            // Rename legacy file so we don't migrate again
            File.Move(legacyPath, legacyPath + ".migrated");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to migrate legacy transcripts.json");
        }
    }

    private static string GetDefaultDirectory()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(appData, "MarsinDictation", "transcripts");
    }
}
