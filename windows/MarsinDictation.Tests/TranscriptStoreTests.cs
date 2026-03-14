using MarsinDictation.Core.History;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using Xunit.Abstractions;

namespace MarsinDictation.Tests;

/// <summary>
/// Tests for the TranscriptStore — the local history of all dictation transcriptions.
///
/// These tests verify that:
///   - Entries are stored newest-first (for quick access via recovery hotkey)
///   - Entries can be filtered by state (Pending, Success, Failed)
///   - State transitions persist to disk (Pending → Success after transcription)
///   - The store survives app restarts (JSON round-trip)
///   - Clear wipes all data from memory AND disk (privacy)
///   - Recovery behavior prioritizes newest Pending transcript
///   - Corrupt JSON files do not crash the app
///
/// Without these tests, a broken store would silently lose transcript history,
/// corrupt the recovery hotkey's ability to find recent transcriptions, or
/// leave data on disk after the user requests a wipe.
/// </summary>
public class TranscriptStoreTests : EvidenceTest, IDisposable
{
    private readonly string _testDir;
    private readonly string _shardDir;
    private readonly TranscriptStore _store;

    public TranscriptStoreTests(ITestOutputHelper output) : base(output)
    {
        _testDir = Path.Combine(Path.GetTempPath(), "MarsinDictation_Tests_" + Guid.NewGuid().ToString("N"));
        _shardDir = Path.Combine(_testDir, "transcripts");
        _store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }

    [Fact]
    public void Add_InsertsAtFront()
    {
        Setup("Empty TranscriptStore, no entries");
        Intent("New transcriptions should appear at the top of the list (newest first for quick access)");
        Expect("After adding 'first' then 'second', the list order is [second, first]");

        var entry1 = TranscriptEntry.Create("first", "openai", "whisper-1", TranscriptState.Success);
        var entry2 = TranscriptEntry.Create("second", "openai", "whisper-1", TranscriptState.Success);

        _store.Add(entry1);
        _store.Add(entry2);

        AssertEvidence("Total entries", 2, _store.Entries.Count);
        AssertEvidence("Entries[0] (most recent)", "second", _store.Entries[0].Text);
        AssertEvidence("Entries[1] (oldest)", "first", _store.Entries[1].Text);
        Pass("newest entry 'second' is at index 0, oldest 'first' at index 1");
    }

    [Fact]
    public void GetMostRecent_FiltersByState()
    {
        Setup("TranscriptStore with 2 entries: one Success, one Pending");
        Intent("The recovery hotkey needs to find the most recent transcript by state (e.g., only pending ones)");
        Expect("Filtering by Pending returns 'pending text', filtering by FailedTranscription returns null");

        _store.Add(TranscriptEntry.Create("success text", "openai", "whisper-1", TranscriptState.Success));
        _store.Add(TranscriptEntry.Create("pending text", "openai", "whisper-1", TranscriptState.Pending));

        var pending = _store.GetMostRecent(TranscriptState.Pending);
        AssertEvidence("Found pending entry", true, pending != null);
        AssertEvidence("Pending entry text", "pending text", pending!.Text);

        var failed = _store.GetMostRecent(TranscriptState.FailedTranscription);
        AssertEvidence("FailedTranscription entry exists", false, failed != null);
        Pass("Pending filter → 'pending text', FailedTranscription filter → null (correct)");
    }

    [Fact]
    public void RecoveryPrefersMostRecentPendingTranscript()
    {
        Setup("TranscriptStore with 3 entries: 1 older Success, 1 older Pending, 1 newest Pending");
        Intent("Recovery should return the most recent Pending transcript, not the newest Success transcript");
        Expect("GetMostRecent(Pending) returns the newest Pending entry, ignoring Success entries");

        _store.Add(TranscriptEntry.Create("older success", "openai", "whisper-1", TranscriptState.Success));
        _store.Add(TranscriptEntry.Create("older pending", "openai", "whisper-1", TranscriptState.Pending));
        _store.Add(TranscriptEntry.Create("newer pending", "openai", "whisper-1", TranscriptState.Pending));

        var mostRecentSuccess = _store.GetMostRecent(TranscriptState.Success);
        var mostRecentPending = _store.GetMostRecent(TranscriptState.Pending);

        Got("Most recent Success", mostRecentSuccess?.Text);
        Got("Most recent Pending", mostRecentPending?.Text);

        AssertEvidence("Recovery selected (most recent Pending)", "newer pending", mostRecentPending!.Text);
        AssertEvidence("Recovery did NOT select Success", "older success", mostRecentSuccess!.Text);
        Pass("recovery correctly prioritized newest Pending transcript over Success entries");
    }

    [Fact]
    public void UpdateState_ChangesStateAndPersists()
    {
        Setup("TranscriptStore with 1 entry in Pending state (simulating transcription in progress)");
        Intent("After transcription completes, the entry's state should update from Pending → Success");
        Expect("UpdateState returns true, entry state changes to Success");

        var entry = TranscriptEntry.Create("test", "openai", "whisper-1", TranscriptState.Pending);
        _store.Add(entry);
        Got("Initial entry state", _store.Entries[0].State);

        var updated = _store.UpdateState(entry.Id, TranscriptState.Success);
        AssertEvidence("UpdateState returned true", true, updated);
        AssertEvidence("Entry state after update", TranscriptState.Success, _store.Entries[0].State);
        Pass("Pending → Success transition applied, UpdateState returned true");
    }

    [Fact]
    public void UpdateState_ReturnsFalseForUnknownId()
    {
        Setup("Empty TranscriptStore, no entries at all");
        Intent("Updating a non-existent entry should fail gracefully (return false) instead of crashing");
        Expect("UpdateState with bogus ID returns false, no exception thrown");

        var result = _store.UpdateState("nonexistent-id", TranscriptState.Success);
        AssertEvidence("UpdateState('nonexistent-id')", false, result);
        Pass("returned false for unknown ID, no crash");
    }

    [Fact]
    public void Persistence_RoundTrip()
    {
        Setup("TranscriptStore with temp directory on disk, 2 entries about to be saved as JSONL shards");
        Intent("Transcript history should survive an app restart (save to JSONL → reload from JSONL)");
        Expect("A new TranscriptStore reading the same directory recovers both entries with correct text, state, and order");

        _store.Add(TranscriptEntry.Create("hello world", "localai", "whisper-1", TranscriptState.Success));
        _store.Add(TranscriptEntry.Create("pending text", "openai", "gpt-4o-mini-transcribe", TranscriptState.Pending));

        Got("Shard directory exists", Directory.Exists(_shardDir));
        var shardFiles = Directory.GetFiles(_shardDir, "*.jsonl");
        Got("Shard file count", shardFiles.Length);

        // Simulate app restart — new instance, same directory
        var store2 = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
        store2.Load();

        AssertEvidence("Entries after reload", 2, store2.Entries.Count);
        AssertEvidence("Entry[0] text", "pending text", store2.Entries[0].Text);
        AssertEvidence("Entry[0] state", TranscriptState.Pending, store2.Entries[0].State);
        AssertEvidence("Entry[1] text", "hello world", store2.Entries[1].Text);
        AssertEvidence("Entry[1] state", TranscriptState.Success, store2.Entries[1].State);
        Pass("both entries recovered with correct text, state, and order after reload");
    }

    [Fact]
    public void Clear_RemovesAll_AndPersistsEmptyStore()
    {
        Setup("TranscriptStore with 2 entries saved to disk as JSONL (simulating user requesting privacy wipe)");
        Intent("Clear should wipe all transcript history from memory AND delete all shard files from disk");
        Expect("After Clear, in-memory count is 0 AND reloading from disk also yields 0 entries");

        _store.Add(TranscriptEntry.Create("entry1", "openai", "whisper-1", TranscriptState.Success));
        _store.Add(TranscriptEntry.Create("entry2", "openai", "whisper-1", TranscriptState.Pending));
        Got("Entries before clear", _store.Entries.Count);
        Got("Shard directory exists before clear", Directory.Exists(_shardDir));

        _store.Clear();
        AssertEvidence("In-memory entries after clear", 0, _store.Entries.Count);

        // Verify disk was also cleared
        var store2 = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
        store2.Load();
        AssertEvidence("Entries after reload from disk", 0, store2.Entries.Count);
        Pass("Clear wiped memory AND disk — reloaded store is also empty (privacy wipe confirmed)");
    }

    [Fact]
    public void Load_CorruptJson_FallsBackGracefully()
    {
        Setup("Transcript shard file exists but contains invalid JSON garbage");
        Intent("When a shard file is corrupted, Load should not crash and should leave the store empty");
        Expect("After loading corrupt shard, Entries count is 0, no exception thrown");

        Directory.CreateDirectory(_shardDir);
        var corruptShard = Path.Combine(_shardDir, "2026-03.jsonl");
        File.WriteAllText(corruptShard, "{{{{ not valid json !!! }}}}");
        Got("Corrupt shard written", corruptShard);
        Got("File contents", File.ReadAllText(corruptShard));

        var store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
        store.Load(); // should not throw

        AssertEvidence("Entries after loading corrupt shard", 0, store.Entries.Count);
        Pass("corrupt JSONL did not crash — store is empty and app can continue normally");
    }

    [Fact]
    public void Load_EmptyFile_FallsBackGracefully()
    {
        Setup("Transcript shard file exists but is completely empty (0 bytes, simulating interrupted write)");
        Intent("An empty shard file should not crash the app");
        Expect("After loading empty shard, Entries count is 0");

        Directory.CreateDirectory(_shardDir);
        var emptyShard = Path.Combine(_shardDir, "2026-03.jsonl");
        File.WriteAllText(emptyShard, "");
        Got("File size (bytes)", new FileInfo(emptyShard).Length);

        var store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
        store.Load(); // should not throw

        AssertEvidence("Entries after loading empty shard", 0, store.Entries.Count);
        Pass("empty shard did not crash — store is empty and app can start fresh");
    }

    // ── New JSONL-specific tests ────────────────────────────────

    [Fact]
    public void Add_CreatesMonthlyShardFile()
    {
        Setup("Empty TranscriptStore, no shard files on disk");
        Intent("Adding an entry should create a JSONL shard file named after the current month (e.g., 2026-03.jsonl)");
        Expect("Exactly 1 .jsonl file exists in the shard directory, named with the current year-month");

        _store.Add(TranscriptEntry.Create("shard test", "openai", "gpt-4o-mini-transcribe", TranscriptState.Success));

        AssertEvidence("Shard directory exists", true, Directory.Exists(_shardDir));
        var shardFiles = Directory.GetFiles(_shardDir, "*.jsonl");
        AssertEvidence("Shard file count", 1, shardFiles.Length);

        var expectedName = DateTimeOffset.UtcNow.ToString("yyyy-MM") + ".jsonl";
        var actualName = Path.GetFileName(shardFiles[0]);
        AssertEvidence("Shard filename", expectedName, actualName);

        // Verify the shard contains valid JSONL
        var lines = File.ReadAllLines(shardFiles[0]).Where(l => !string.IsNullOrWhiteSpace(l)).ToArray();
        AssertEvidence("Lines in shard", 1, lines.Length);
        Got("Shard content", lines[0]);
        Pass("entry was written to a correctly-named monthly shard file");
    }

    [Fact]
    public void Add_AppendsToExistingShard()
    {
        Setup("TranscriptStore with 1 entry already saved to current month's shard");
        Intent("Adding a second entry in the same month should APPEND to the existing shard, not overwrite it");
        Expect("The shard file contains 2 JSONL lines after adding 2 entries");

        _store.Add(TranscriptEntry.Create("first", "openai", "whisper-1", TranscriptState.Success));
        _store.Add(TranscriptEntry.Create("second", "openai", "whisper-1", TranscriptState.Success));

        var shardFiles = Directory.GetFiles(_shardDir, "*.jsonl");
        AssertEvidence("Shard file count", 1, shardFiles.Length);

        var lines = File.ReadAllLines(shardFiles[0]).Where(l => !string.IsNullOrWhiteSpace(l)).ToArray();
        AssertEvidence("Lines in shard", 2, lines.Length);
        Got("Line 1 preview", lines[0][..Math.Min(80, lines[0].Length)]);
        Got("Line 2 preview", lines[1][..Math.Min(80, lines[1].Length)]);
        Pass("second entry was appended to shard (not overwritten) — 2 JSONL lines present");
    }

    [Fact]
    public void Load_MultipleShards_MergesNewestFirst()
    {
        Setup("Two shard files on disk: 2025-12.jsonl (1 old entry) and 2026-03.jsonl (1 new entry)");
        Intent("Loading should merge entries from all shards and sort newest first across months");
        Expect("2 entries loaded, newest (March 2026) first, oldest (Dec 2025) second");

        Directory.CreateDirectory(_shardDir);

        // Write an "old" entry to a Dec 2025 shard
        var oldEntry = new TranscriptEntry
        {
            Id = Guid.NewGuid().ToString("N"),
            CreatedAt = new DateTimeOffset(2025, 12, 15, 10, 0, 0, TimeSpan.Zero),
            Text = "old entry from december",
            Provider = "openai",
            Model = "whisper-1",
            State = TranscriptState.Success
        };
        var oldJson = System.Text.Json.JsonSerializer.Serialize(oldEntry,
            new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase });
        File.WriteAllText(Path.Combine(_shardDir, "2025-12.jsonl"), oldJson + "\n");

        // Write a "new" entry to a Mar 2026 shard
        var newEntry = new TranscriptEntry
        {
            Id = Guid.NewGuid().ToString("N"),
            CreatedAt = new DateTimeOffset(2026, 3, 14, 10, 0, 0, TimeSpan.Zero),
            Text = "new entry from march",
            Provider = "openai",
            Model = "gpt-4o-mini-transcribe",
            State = TranscriptState.Pending
        };
        var newJson = System.Text.Json.JsonSerializer.Serialize(newEntry,
            new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase });
        File.WriteAllText(Path.Combine(_shardDir, "2026-03.jsonl"), newJson + "\n");

        Got("Shard files on disk", Directory.GetFiles(_shardDir, "*.jsonl").Length);

        var store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
        store.Load();

        AssertEvidence("Total entries loaded", 2, store.Entries.Count);
        AssertEvidence("Entry[0] text (newest)", "new entry from march", store.Entries[0].Text);
        AssertEvidence("Entry[1] text (oldest)", "old entry from december", store.Entries[1].Text);
        Pass("entries from multiple shards merged and sorted newest-first across months");
    }

    [Fact]
    public void LegacyMigration_ConvertsJsonToJsonl()
    {
        Setup("Legacy transcripts.json exists in parent directory with 3 entries (pre-JSONL format)");
        Intent("On first load, the store should auto-migrate legacy JSON to JSONL shards and rename the old file");
        Expect("3 entries loaded from JSONL shards, legacy file renamed to .migrated");

        // The legacy file sits in the PARENT of the shard directory
        // (shard dir = .../transcripts/, legacy = .../transcripts.json)
        Directory.CreateDirectory(_testDir);
        var legacyPath = Path.Combine(_testDir, "transcripts.json");

        var legacyEntries = new[]
        {
            new TranscriptEntry
            {
                Id = Guid.NewGuid().ToString("N"),
                CreatedAt = new DateTimeOffset(2026, 2, 10, 8, 0, 0, TimeSpan.Zero),
                Text = "february entry", Provider = "openai", Model = "whisper-1", State = TranscriptState.Success
            },
            new TranscriptEntry
            {
                Id = Guid.NewGuid().ToString("N"),
                CreatedAt = new DateTimeOffset(2026, 3, 5, 9, 0, 0, TimeSpan.Zero),
                Text = "march entry one", Provider = "openai", Model = "whisper-1", State = TranscriptState.Pending
            },
            new TranscriptEntry
            {
                Id = Guid.NewGuid().ToString("N"),
                CreatedAt = new DateTimeOffset(2026, 3, 12, 14, 0, 0, TimeSpan.Zero),
                Text = "march entry two", Provider = "openai", Model = "gpt-4o-mini-transcribe", State = TranscriptState.Success
            }
        };

        var json = System.Text.Json.JsonSerializer.Serialize(legacyEntries, new System.Text.Json.JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
        });
        File.WriteAllText(legacyPath, json);
        Got("Legacy file size (bytes)", new FileInfo(legacyPath).Length);

        // Load should trigger migration
        var store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
        store.Load();

        AssertEvidence("Total entries loaded", 3, store.Entries.Count);

        // Should have 2 shard files: 2026-02.jsonl and 2026-03.jsonl
        var shardFiles = Directory.GetFiles(_shardDir, "*.jsonl").OrderBy(f => f).ToArray();
        AssertEvidence("Shard file count", 2, shardFiles.Length);
        Got("Shard 1", Path.GetFileName(shardFiles[0]));
        Got("Shard 2", Path.GetFileName(shardFiles[1]));

        // Legacy file should be renamed
        AssertEvidence("Legacy file gone", false, File.Exists(legacyPath));
        AssertEvidence("Legacy .migrated exists", true, File.Exists(legacyPath + ".migrated"));
        Pass("legacy transcripts.json migrated to 2 JSONL shards, old file renamed to .migrated");
    }

    [Fact]
    public void Clear_DeletesAllShardFiles()
    {
        Setup("TranscriptStore with entries in 2 different month shards");
        Intent("Clear should delete ALL shard files from disk, not just the current month");
        Expect("After Clear, shard directory exists but contains 0 .jsonl files");

        // Manually create 2 shards
        Directory.CreateDirectory(_shardDir);
        File.WriteAllText(Path.Combine(_shardDir, "2025-11.jsonl"), "{\"id\":\"a\",\"text\":\"old\"}\n");
        File.WriteAllText(Path.Combine(_shardDir, "2026-03.jsonl"), "{\"id\":\"b\",\"text\":\"new\"}\n");
        Got("Shard files before clear", Directory.GetFiles(_shardDir, "*.jsonl").Length);

        var store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _shardDir);
        store.Load();
        Got("Entries loaded", store.Entries.Count);

        store.Clear();

        var remaining = Directory.GetFiles(_shardDir, "*.jsonl");
        AssertEvidence("Shard files after clear", 0, remaining.Length);
        AssertEvidence("In-memory entries after clear", 0, store.Entries.Count);
        Pass("Clear deleted ALL shard files from disk — complete privacy wipe");
    }
}
