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
    private readonly string _testFilePath;
    private readonly TranscriptStore _store;

    public TranscriptStoreTests(ITestOutputHelper output) : base(output)
    {
        _testDir = Path.Combine(Path.GetTempPath(), "MarsinDictation_Tests_" + Guid.NewGuid().ToString("N"));
        _testFilePath = Path.Combine(_testDir, "transcripts.json");
        _store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _testFilePath);
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
        Setup("TranscriptStore with temp file on disk, 2 entries about to be saved");
        Intent("Transcript history should survive an app restart (save to JSON → reload from JSON)");
        Expect("A new TranscriptStore reading the same file recovers both entries with correct text, state, and order");

        _store.Add(TranscriptEntry.Create("hello world", "localai", "whisper-1", TranscriptState.Success));
        _store.Add(TranscriptEntry.Create("pending text", "openai", "gpt-4o-mini-transcribe", TranscriptState.Pending));

        Got("File exists on disk", File.Exists(_testFilePath));
        Got("File size (bytes)", new FileInfo(_testFilePath).Length);

        // Simulate app restart — new instance, same file
        var store2 = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _testFilePath);
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
        Setup("TranscriptStore with 2 entries saved to disk (simulating user requesting privacy wipe)");
        Intent("Clear should wipe all transcript history from memory AND persist the empty state to disk");
        Expect("After Clear, in-memory count is 0 AND reloading from disk also yields 0 entries");

        _store.Add(TranscriptEntry.Create("entry1", "openai", "whisper-1", TranscriptState.Success));
        _store.Add(TranscriptEntry.Create("entry2", "openai", "whisper-1", TranscriptState.Pending));
        Got("Entries before clear", _store.Entries.Count);
        Got("File exists before clear", File.Exists(_testFilePath));

        _store.Clear();
        AssertEvidence("In-memory entries after clear", 0, _store.Entries.Count);

        // Verify disk was also cleared
        var store2 = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _testFilePath);
        store2.Load();
        AssertEvidence("Entries after reload from disk", 0, store2.Entries.Count);
        Pass("Clear wiped memory AND disk — reloaded store is also empty (privacy wipe confirmed)");
    }

    [Fact]
    public void Load_CorruptJson_FallsBackGracefully()
    {
        Setup("Transcript file exists but contains invalid JSON garbage");
        Intent("When the transcript file is corrupted, Load should not crash and should leave the store empty");
        Expect("After loading corrupt file, Entries count is 0, no exception thrown");

        Directory.CreateDirectory(_testDir);
        File.WriteAllText(_testFilePath, "{{{{ not valid json !!! }}}}");
        Got("Corrupt file written", _testFilePath);
        Got("File contents", File.ReadAllText(_testFilePath));

        var store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _testFilePath);
        store.Load(); // should not throw

        AssertEvidence("Entries after loading corrupt file", 0, store.Entries.Count);
        Pass("corrupt JSON did not crash — store is empty and app can continue normally");
    }

    [Fact]
    public void Load_EmptyFile_FallsBackGracefully()
    {
        Setup("Transcript file exists but is completely empty (0 bytes, simulating interrupted write)");
        Intent("An empty transcript file should not crash the app");
        Expect("After loading empty file, Entries count is 0");

        Directory.CreateDirectory(_testDir);
        File.WriteAllText(_testFilePath, "");
        Got("File size (bytes)", new FileInfo(_testFilePath).Length);

        var store = new TranscriptStore(NullLogger<TranscriptStore>.Instance, _testFilePath);
        store.Load(); // should not throw

        AssertEvidence("Entries after loading empty file", 0, store.Entries.Count);
        Pass("empty file did not crash — store is empty and app can start fresh");
    }
}
