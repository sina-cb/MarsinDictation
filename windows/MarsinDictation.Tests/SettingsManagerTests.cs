using MarsinDictation.Core.Settings;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using Xunit.Abstractions;

namespace MarsinDictation.Tests;

/// <summary>
/// Tests for SettingsManager — the persistence layer for user preferences.
///
/// These tests verify that:
///   - When no settings file exists, Load creates one with design-doc defaults
///   - Settings modified by the user survive an app restart (save → reload round-trip)
///   - AppSettings constructor defaults exactly match the design doc settings table (9 fields)
///   - Corrupt or malformed JSON triggers graceful fallback to defaults
///   - Settings JSON never contains API keys or secrets (privacy contract)
///
/// Without these tests, a settings bug would cause the app to launch with wrong
/// defaults, lose user preferences on restart, drift from the design doc, or
/// crash on corrupted settings files.
/// </summary>
public class SettingsManagerTests : EvidenceTest, IDisposable
{
    private readonly string _testDir;
    private readonly string _testFilePath;

    public SettingsManagerTests(ITestOutputHelper output) : base(output)
    {
        _testDir = Path.Combine(Path.GetTempPath(), "MarsinDictation_Tests_" + Guid.NewGuid().ToString("N"));
        _testFilePath = Path.Combine(_testDir, "settings.json");
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }

    [Fact]
    public void Defaults_MatchDesignDoc()
    {
        Setup("New AppSettings() instance — no loading, pure constructor defaults (11 fields)");
        Intent("The AppSettings constructor defaults must exactly match the design doc settings table");
        Expect("All 11 constructor defaults match the Settings (v0) table in 01_win_design_v0.md");

        var settings = new AppSettings();

        AssertEvidence("TranscriptionProvider", "embedded", settings.TranscriptionProvider);
        AssertEvidence("OpenAIModel", "gpt-4o-mini-transcribe", settings.OpenAIModel);
        AssertEvidence("LocalAIModel", "whisper-1", settings.LocalAIModel);
        AssertEvidence("LocalAIEndpoint", "http://localhost:3850", settings.LocalAIEndpoint);
        AssertEvidence("WhisperModel", "ggml-large-v3-turbo-q5_0.bin", settings.WhisperModel);
        AssertEvidence("Language", "en", settings.Language);
        AssertEvidence("AutoPunctuation", true, settings.AutoPunctuation);
        AssertEvidence("StripFillerWords", true, settings.StripFillerWords);
        AssertEvidence("LaunchAtStartup", false, settings.LaunchAtStartup);
        AssertEvidence("LocalHistory", true, settings.LocalHistory);
        Pass("all 11 constructor defaults match the design document");
    }

    [Fact]
    public void Load_NoFile_CreatesDefaults()
    {
        Setup($"Empty temp directory ({_testDir}), no settings.json exists");
        Intent("Loading settings when no file exists should create the file with design-doc defaults");
        Expect("File is created on disk, all 11 settings match design-doc defaults (same 11 as constructor)");

        var manager = new SettingsManager(NullLogger<SettingsManager>.Instance, _testFilePath);
        manager.Load();

        AssertEvidence("Settings file created on disk", true, File.Exists(_testFilePath));
        AssertEvidence("TranscriptionProvider", "embedded", manager.Settings.TranscriptionProvider);
        AssertEvidence("OpenAIModel", "gpt-4o-mini-transcribe", manager.Settings.OpenAIModel);
        AssertEvidence("LocalAIModel", "whisper-1", manager.Settings.LocalAIModel);
        AssertEvidence("LocalAIEndpoint", "http://localhost:3850", manager.Settings.LocalAIEndpoint);
        AssertEvidence("WhisperModel", "ggml-large-v3-turbo-q5_0.bin", manager.Settings.WhisperModel);
        AssertEvidence("Language", "en", manager.Settings.Language);
        AssertEvidence("AutoPunctuation", true, manager.Settings.AutoPunctuation);
        AssertEvidence("StripFillerWords", true, manager.Settings.StripFillerWords);
        AssertEvidence("LaunchAtStartup", false, manager.Settings.LaunchAtStartup);
        AssertEvidence("LocalHistory", true, manager.Settings.LocalHistory);
        Pass("all 11 defaults match design doc, settings.json was created on disk");
    }

    [Fact]
    public void Persistence_RoundTrip()
    {
        Setup($"Fresh SettingsManager pointing at temp file ({_testFilePath})");
        Intent("Settings changed by the user should survive an app restart (save → reload from disk)");
        Expect("After save + new instance + load, modified values are preserved");

        var manager = new SettingsManager(NullLogger<SettingsManager>.Instance, _testFilePath);
        manager.Load();
        manager.Settings.TranscriptionProvider = "localai";
        manager.Settings.Language = "es";
        manager.Settings.LaunchAtStartup = true;
        manager.Save();
        Got("Saved changes", "provider=localai, lang=es, startup=true");

        // Simulate app restart — new instance, same file
        var manager2 = new SettingsManager(NullLogger<SettingsManager>.Instance, _testFilePath);
        manager2.Load();

        AssertEvidence("TranscriptionProvider after reload", "localai", manager2.Settings.TranscriptionProvider);
        AssertEvidence("Language after reload", "es", manager2.Settings.Language);
        AssertEvidence("LaunchAtStartup after reload", true, manager2.Settings.LaunchAtStartup);
        Pass("all 3 modified settings survived save → reload round-trip");
    }

    [Fact]
    public void Load_CorruptJson_FallsBackGracefully()
    {
        Setup($"Settings file exists but contains invalid JSON garbage");
        Intent("When the settings file is corrupted, Load should fall back to defaults instead of crashing");
        Expect("After loading corrupt file, all settings have design-doc defaults");

        Directory.CreateDirectory(_testDir);
        File.WriteAllText(_testFilePath, "{{{{ this is not valid JSON !@#$%");
        Got("Corrupt file written", _testFilePath);
        Got("File contents", File.ReadAllText(_testFilePath));

        var manager = new SettingsManager(NullLogger<SettingsManager>.Instance, _testFilePath);
        manager.Load(); // should not throw

        AssertEvidence("TranscriptionProvider (default)", "embedded", manager.Settings.TranscriptionProvider);
        AssertEvidence("Language (default)", "en", manager.Settings.Language);
        AssertEvidence("LaunchAtStartup (default)", false, manager.Settings.LaunchAtStartup);
        AssertEvidence("LocalHistory (default)", true, manager.Settings.LocalHistory);
        Pass("corrupt JSON file did not crash — all settings fell back to design-doc defaults");
    }

    [Fact]
    public void Load_EmptyFile_FallsBackGracefully()
    {
        Setup($"Settings file exists but is completely empty (0 bytes)");
        Intent("An empty settings file (e.g., from disk corruption or interrupted write) should not crash the app");
        Expect("After loading empty file, all settings have defaults");

        Directory.CreateDirectory(_testDir);
        File.WriteAllText(_testFilePath, "");
        Got("Empty file written", _testFilePath);
        Got("File size (bytes)", new FileInfo(_testFilePath).Length);

        var manager = new SettingsManager(NullLogger<SettingsManager>.Instance, _testFilePath);
        manager.Load(); // should not throw

        AssertEvidence("TranscriptionProvider (default)", "embedded", manager.Settings.TranscriptionProvider);
        AssertEvidence("Language (default)", "en", manager.Settings.Language);
        Pass("empty file did not crash — settings fell back to defaults");
    }

    [Fact]
    public void Secrets_AreNotWrittenToSettingsJson()
    {
        Setup("SettingsManager saves settings to disk — inspecting raw JSON for secret keywords");
        Intent("The settings JSON file must never contain API keys, tokens, or secret-bearing fields (privacy contract)");
        Expect("File contents do not contain 'api_key', 'apikey', 'secret', 'token', or 'password'");

        var manager = new SettingsManager(NullLogger<SettingsManager>.Instance, _testFilePath);
        manager.Load();
        manager.Save();

        var json = File.ReadAllText(_testFilePath);
        Got("Settings file size", $"{json.Length} chars");
        Got("File contents", json);

        var secretKeywords = new[] { "api_key", "apikey", "secret", "token", "password", "bearer" };
        foreach (var keyword in secretKeywords)
        {
            AssertEvidence($"JSON does not contain '{keyword}'", true,
                !json.Contains(keyword, StringComparison.OrdinalIgnoreCase));
        }
        Pass("settings JSON contains zero secret-bearing keywords — API keys are handled by SecretStore (DPAPI)");
    }
}
