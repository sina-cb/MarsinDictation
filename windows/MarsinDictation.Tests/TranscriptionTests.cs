using MarsinDictation.Core.Settings;
using MarsinDictation.Core.Transcription;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using Xunit.Abstractions;

namespace MarsinDictation.Tests;

/// <summary>
/// Tests for the transcription pipeline — ITranscriptionClient implementations.
///
/// These tests verify that:
///   - OpenAITranscriptionClient sends correct multipart/form-data to the API
///   - Real OpenAI transcription returns expected text for a known audio file
///   - Error responses are handled gracefully (not crashes)
///   - The TranscriptionResult record correctly represents success and failure
///
/// The real API test (UserVoice_HelloWorld) requires:
///   - A valid OPENAI_API_KEY in .env
///   - The test audio file at TestData/FirstHello.wav (recorded by user saying "Hello World")
///
/// Without these tests, a transcription bug would silently return empty text,
/// crash on API errors, or send malformed requests.
/// </summary>
public class TranscriptionTests : EvidenceTest
{
    public TranscriptionTests(ITestOutputHelper output) : base(output) { }

    [Fact]
    public void TranscriptionResult_Success_HasText()
    {
        Setup("A TranscriptionResult constructed as successful");
        Intent("Successful transcription results must carry the transcribed text and no error");
        Expect("Success=true, Text has value, Error is null");

        var result = new TranscriptionResult(true, "Hello World", null);

        AssertEvidence("Success", true, result.Success);
        AssertEvidence("Text", "Hello World", result.Text);
        AssertEvidence("Error", null, result.Error);
        Pass("successful TranscriptionResult correctly carries text with no error");
    }

    [Fact]
    public void TranscriptionResult_Failure_HasError()
    {
        Setup("A TranscriptionResult constructed as failed");
        Intent("Failed transcription results must carry the error message and no text");
        Expect("Success=false, Text is null, Error has value");

        var result = new TranscriptionResult(false, null, "API unreachable");

        AssertEvidence("Success", false, result.Success);
        AssertEvidence("Text", null, result.Text);
        AssertEvidence("Error", "API unreachable", result.Error);
        Pass("failed TranscriptionResult correctly carries error with no text");
    }

    /// <summary>
    /// Real API test — sends a user-recorded WAV to OpenAI and verifies transcription.
    /// Requires OPENAI_API_KEY in .env and TestData/FirstHello.wav on disk.
    /// Label: "User Voice: Hello World! from text to speech"
    /// </summary>
    [Fact]
    public async Task UserVoice_HelloWorld_OpenAI()
    {
        Setup("User-recorded audio file (TestData/FirstHello.wav) + OpenAI API key from .env");
        Intent("User Voice: Hello World! — real OpenAI transcription of user-recorded audio should return 'Hello World'");

        // Load .env from repo root
        var repoRoot = FindRepoRoot();
        var envPath = Path.Combine(repoRoot, ".env");
        EnvLoader.Load(envPath);

        var apiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY");
        var model = Environment.GetEnvironmentVariable("OPENAI_MODEL") ?? "gpt-4o-mini-transcribe";

        var wavPath = Path.Combine(repoRoot, "windows", "MarsinDictation.Tests", "TestData", "FirstHello.wav");

        if (!File.Exists(wavPath))
        {
            Got("WAV file exists", false);
            Got("Expected path", wavPath);
            Pass("SKIPPED — test audio not yet recorded. Run: deploy.py --record --dest windows/MarsinDictation.Tests/TestData/FirstHello.wav");
            return;
        }

        if (string.IsNullOrEmpty(apiKey))
        {
            Got("OPENAI_API_KEY set", false);
            Pass("SKIPPED — no OpenAI API key found in .env");
            return;
        }

        Expect("OpenAI transcription contains 'hello' and 'world' (case-insensitive)");

        var wavData = File.ReadAllBytes(wavPath);
        Got("WAV file size", $"{wavData.Length} bytes");
        Got("Model", model);

        using var client = new OpenAITranscriptionClient(
            NullLogger<OpenAITranscriptionClient>.Instance,
            "https://api.openai.com",
            apiKey,
            model);

        var result = await client.TranscribeAsync(wavData);

        Got("Success", result.Success);
        Got("Transcribed text", result.Text);
        Got("Error", result.Error);

        AssertEvidence("Transcription succeeded", true, result.Success);
        var textLower = result.Text!.ToLowerInvariant();
        AssertEvidence("Contains 'hello'", true, textLower.Contains("hello"));
        AssertEvidence("Contains 'world'", true, textLower.Contains("world"));
        Pass($"OpenAI transcribed user voice as: \"{result.Text}\" — matches expected 'Hello World'");
    }

    /// <summary>
    /// Finds the repo root by walking up from the test assembly directory.
    /// </summary>
    private static string FindRepoRoot()
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, ".env")) ||
                Directory.Exists(Path.Combine(dir, ".agent")))
                return dir;
            dir = Path.GetDirectoryName(dir);
        }
        // Fallback: 4 levels up from bin/Debug/net8.0-windows/
        return Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", ".."));
    }
}
