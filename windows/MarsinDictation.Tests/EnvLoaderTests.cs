using MarsinDictation.Core.Settings;
using Xunit;
using Xunit.Abstractions;

namespace MarsinDictation.Tests;

/// <summary>
/// Tests for EnvLoader — the .env file parser that sets environment variables at app startup.
///
/// These tests verify that:
///   - KEY=VALUE pairs are parsed and set as environment variables
///   - Comments (#) and blank lines are skipped
///   - Existing environment variables are NOT overridden (system-level takes precedence)
///   - Missing .env file does not crash the app
///
/// Without these tests, a broken .env parser would silently fail to load API keys,
/// causing transcription to fail with confusing errors.
/// </summary>
public class EnvLoaderTests : EvidenceTest, IDisposable
{
    private readonly string _testDir;
    private readonly string _envPath;
    private readonly List<string> _setKeys = new();

    public EnvLoaderTests(ITestOutputHelper output) : base(output)
    {
        _testDir = Path.Combine(Path.GetTempPath(), "MarsinDictation_Tests_" + Guid.NewGuid().ToString("N"));
        _envPath = Path.Combine(_testDir, ".env");
        Directory.CreateDirectory(_testDir);
    }

    public void Dispose()
    {
        // Clean up any env vars we set
        foreach (var key in _setKeys)
            Environment.SetEnvironmentVariable(key, null);
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }

    [Fact]
    public void Load_ParsesKeyValuePairs()
    {
        Setup("A .env file with 3 KEY=VALUE pairs and comments");
        Intent("EnvLoader should parse valid KEY=VALUE lines and set them as environment variables");
        Expect("All 3 keys are set, comments and blank lines are ignored");

        var uniquePrefix = $"MTEST_{Guid.NewGuid():N}_";
        var key1 = uniquePrefix + "PROVIDER";
        var key2 = uniquePrefix + "MODEL";
        var key3 = uniquePrefix + "ENDPOINT";
        _setKeys.AddRange(new[] { key1, key2, key3 });

        File.WriteAllText(_envPath, $"""
            # This is a comment
            {key1}=openai

            {key2}=gpt-4o-mini-transcribe
            # Another comment
            {key3}=http://localhost:8080
            """);

        EnvLoader.Load(_envPath);

        AssertEvidence(key1, "openai", Environment.GetEnvironmentVariable(key1));
        AssertEvidence(key2, "gpt-4o-mini-transcribe", Environment.GetEnvironmentVariable(key2));
        AssertEvidence(key3, "http://localhost:8080", Environment.GetEnvironmentVariable(key3));
        Pass("all 3 KEY=VALUE pairs parsed, comments and blank lines ignored");
    }

    [Fact]
    public void Load_DoesNotOverrideExistingVars()
    {
        Setup("An environment variable already set before .env is loaded");
        Intent("EnvLoader must NOT override existing env vars — system-level config takes precedence");
        Expect("Pre-existing value is preserved, .env value is ignored");

        var key = $"MTEST_{Guid.NewGuid():N}_EXISTING";
        _setKeys.Add(key);
        Environment.SetEnvironmentVariable(key, "system_value");

        File.WriteAllText(_envPath, $"{key}=env_file_value");
        EnvLoader.Load(_envPath);

        Got("Value after load", Environment.GetEnvironmentVariable(key));
        AssertEvidence("Preserved system value", "system_value", Environment.GetEnvironmentVariable(key));
        Pass("existing env var was NOT overridden by .env file — system_value preserved");
    }

    [Fact]
    public void Load_MissingFile_DoesNotCrash()
    {
        Setup("No .env file exists at the specified path");
        Intent("Loading a missing .env file should be a silent no-op (not all environments use .env)");
        Expect("No exception thrown, no environment variables changed");

        var nonExistent = Path.Combine(_testDir, "nonexistent.env");
        EnvLoader.Load(nonExistent); // should not throw

        Pass("missing .env file did not crash — silent no-op as expected");
    }
}
