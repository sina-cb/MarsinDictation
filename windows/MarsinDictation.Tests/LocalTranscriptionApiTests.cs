using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using MarsinDictation.Core.Api;
using MarsinDictation.Core.Audio;
using MarsinDictation.Core.Transcription;
using Xunit;
using Xunit.Abstractions;

namespace MarsinDictation.Tests;

/// <summary>
/// Real loopback HTTP tests protect the upload-only API, browser isolation, bounded requests,
/// sanitized failures and nonfatal port collision. Fake inference isolates HTTP behavior.
/// The explicitly named installed-model test separately runs real offline Whisper inference.
/// No test invokes OpenAI, captures a microphone, injects text, or changes app settings.
/// </summary>
[Collection("Local transcription API")]
public sealed class LocalTranscriptionApiTests : EvidenceTest
{
    public LocalTranscriptionApiTests(ITestOutputHelper output) : base(output) { }

    private static int FreePort()
    {
        var socket = new TcpListener(IPAddress.Loopback, 0);
        socket.Start();
        int port = ((IPEndPoint)socket.LocalEndpoint).Port;
        socket.Stop();
        return port;
    }

    private static byte[] Wav()
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, Encoding.ASCII, true);
        writer.Write("RIFF"u8); writer.Write(38); writer.Write("WAVEfmt "u8);
        writer.Write(16); writer.Write((short)1); writer.Write((short)1);
        writer.Write(16000); writer.Write(32000); writer.Write((short)2); writer.Write((short)16);
        writer.Write("data"u8); writer.Write(2); writer.Write((short)123);
        return stream.ToArray();
    }

    private static HttpRequestMessage Upload(byte[]? audio = null, string mime = "audio/wav")
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "transcribe")
        { Content = new ByteArrayContent(audio ?? Wav()) };
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mime);
        return request;
    }

    private static (LocalTranscriptionApi Api, HttpClient Client) Start(
        Func<byte[], CancellationToken, Task<TranscriptionResult?>>? transcribe = null,
        bool ready = true, bool available = true)
    {
        int port = FreePort();
        var api = new LocalTranscriptionApi(transcribe ?? ((_, _) =>
            Task.FromResult<TranscriptionResult?>(new(true, "hello world", null))),
            () => ready, available, "ggml-test.bin", "en", "test-1", port);
        Assert.True(api.TryStart(), "test loopback listener must actually start");
        return (api, new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{port}/") });
    }

    [Fact]
    public async Task HealthAndUpload_ReportLocalBackend_WithoutPaths()
    {
        Setup("A real loopback listener with ready fake embedded inference, no cloud client");
        Intent("Health and uploaded WAV use a documented local backend without exposing filesystem paths");
        Expect("200 health with API version 1; 200 upload with text and embedded backend");
        var (api, client) = Start(); using var server = api; using var http = client;
        var health = await http.GetAsync("health");
        AssertEvidence("health HTTP status", HttpStatusCode.OK, health.StatusCode);
        var meta = JsonDocument.Parse(await health.Content.ReadAsStringAsync()).RootElement;
        AssertEvidence("API version", 1, meta.GetProperty("apiVersion").GetInt32());
        AssertEvidence("backend", "embedded-whisper", meta.GetProperty("backend").GetString());
        using var request = Upload();
        var response = await http.SendAsync(request);
        AssertEvidence("upload HTTP status", HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("hello world", body); Assert.DoesNotContain("C:\\", body);
        Assert.Null(response.Headers.AccessControlAllowOrigin());
        Pass("real HTTP health and upload succeeded with safe embedded metadata and no CORS allowance");
    }

    [Theory]
    [InlineData("Origin", "http://127.0.0.1")]
    [InlineData("Origin", "null")]
    [InlineData("Sec-Fetch-Site", "cross-site")]
    [InlineData("Host", "attacker.test")]
    public async Task BrowserOrReboundHost_IsRejected(string header, string value)
    {
        Setup($"A loopback upload carrying disallowed browser/host header {header}");
        Intent("A browser page or rebound hostname cannot drive local transcription");
        Expect("HTTP 403 before inference");
        int calls = 0;
        var (api, client) = Start((_, _) => { calls++; return Task.FromResult<TranscriptionResult?>(new(true, "unexpected", null)); });
        using var server = api; using var http = client; using var request = Upload();
        request.Headers.TryAddWithoutValidation(header, value);
        var response = await http.SendAsync(request);
        AssertEvidence("HTTP status", HttpStatusCode.Forbidden, response.StatusCode);
        AssertEvidence("inference calls", 0, calls);
        Pass("untrusted browser or hostname request was rejected before reading audio for inference");
    }

    [Theory]
    [InlineData("bad-wav", 400)]
    [InlineData("oversize", 413)]
    [InlineData("mime", 415)]
    [InlineData("filepath-json", 415)]
    [InlineData("chunked", 411)]
    public async Task InvalidUpload_IsRejectedBeforeInference(string kind, int expected)
    {
        Setup($"A real loopback upload with invalid case {kind}");
        Intent("Malformed, oversized, unbounded or filepath inputs cannot reach embedded inference");
        Expect($"HTTP {expected} and zero inference calls");
        int calls = 0;
        var (api, client) = Start((_, _) => { calls++; return Task.FromResult<TranscriptionResult?>(new(true, "unexpected", null)); });
        using var server = api; using var http = client;
        using var request = kind switch
        {
            "bad-wav" => Upload([1, 2, 3]),
            "oversize" => Upload(new byte[LocalTranscriptionApi.MaxBodyBytes + 1]),
            "mime" => Upload(mime: "audio/mp4"),
            "filepath-json" => Upload(Encoding.UTF8.GetBytes("{\"file\":\"C:\\\\private.wav\"}"), "application/json"),
            _ => Upload()
        };
        if (kind == "chunked") request.Headers.TransferEncodingChunked = true;
        var response = await http.SendAsync(request);
        AssertEvidence("HTTP status", expected, (int)response.StatusCode);
        AssertEvidence("inference calls", 0, calls);
        Pass("invalid upload was rejected at the HTTP boundary before inference");
    }

    [Fact]
    public async Task BusyInference_RejectsSecondApiRequest_AndKeepsHealthAvailable()
    {
        Setup("One admitted upload blocks in fake inference until released");
        Intent("Requests cannot queue an unbounded inference workload or block health");
        Expect("Second upload gets 429, health stays 200, only one inference call");
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        int calls = 0;
        var (api, client) = Start(async (_, ct) =>
        {
            Interlocked.Increment(ref calls); started.SetResult();
            await release.Task.WaitAsync(ct); return new(true, "done", null);
        });
        using var server = api; using var http = client; using var firstRequest = Upload();
        var first = http.SendAsync(firstRequest);
        try
        {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            using var secondRequest = Upload();
            AssertEvidence("second upload HTTP status", HttpStatusCode.TooManyRequests, (await http.SendAsync(secondRequest)).StatusCode);
            AssertEvidence("health HTTP status", HttpStatusCode.OK, (await http.GetAsync("health")).StatusCode);
            AssertEvidence("inference calls", 1, calls);
        }
        finally { release.TrySetResult(); }
        Assert.Equal(HttpStatusCode.OK, (await first).StatusCode);
        Pass("one API request was admitted while health remained responsive and excess work was rejected");
    }

    [Theory]
    [InlineData("failure", 503)]
    [InlineData("throw", 503)]
    [InlineData("empty", 422)]
    [InlineData("busy", 429)]
    public async Task InferenceOutcomes_AreHonestAndSanitized(string outcome, int status)
    {
        Setup($"Embedded callback reports {outcome}, possibly containing a private path in its internal error");
        Intent("No local path, exception or empty transcript is exposed as successful dictation");
        Expect($"HTTP {status} with sanitized error JSON");
        var (api, client) = Start((_, _) => outcome switch
        {
            "throw" => throw new IOException("C:\\private\\model.bin secret"),
            "failure" => Task.FromResult<TranscriptionResult?>(new(false, null, "C:\\private\\model.bin secret")),
            "empty" => Task.FromResult<TranscriptionResult?>(new(true, "[no audio]", null)),
            _ => Task.FromResult<TranscriptionResult?>(null)
        });
        using var server = api; using var http = client; using var request = Upload();
        var response = await http.SendAsync(request);
        AssertEvidence("HTTP status", status, (int)response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("private", body); Assert.DoesNotContain("secret", body);
        Pass("failed, empty or busy inference produced a safe error rather than false successful text");
    }

    [Fact]
    public async Task MissingModel_IsVisible_AndPortCollisionIsNonfatal()
    {
        Setup("A listening API with no embedded model, and a second listener on its exact prefix");
        Intent("Unavailable model and port collision fail visibly without crashing desktop dictation");
        Expect("503 model_missing and TryStart false for the colliding listener");
        var (api, client) = Start(ready: false, available: false);
        using var server = api; using var http = client;
        var health = await http.GetAsync("health");
        AssertEvidence("health HTTP status", HttpStatusCode.ServiceUnavailable, health.StatusCode);
        Assert.Contains("model_missing", await health.Content.ReadAsStringAsync());
        using var collision = new LocalTranscriptionApi((_, _) => Task.FromResult<TranscriptionResult?>(null),
            () => false, false, "none", "en", "test", http.BaseAddress!.Port);
        AssertEvidence("colliding listener started", false, collision.TryStart());
        Pass("model absence was visible and a port collision returned false instead of throwing");
    }

    [Theory]
    [InlineData(0)] [InlineData(4)] [InlineData(22)] [InlineData(24)] [InlineData(28)] [InlineData(32)] [InlineData(34)] [InlineData(40)]
    public void WavValidation_RejectsCorruptedHeader(int offset)
    {
        var wav = Wav(); Assert.True(LocalTranscriptionApi.IsNormalizedWav(wav));
        wav[offset] ^= 0xff;
        Assert.False(LocalTranscriptionApi.IsNormalizedWav(wav));
    }

    [Fact]
    public async Task StalledUpload_ExpiresAndReleasesAdmission()
    {
        Setup("Raw TCP client declares a valid WAV body but sends only its first byte");
        Intent("A stalled HTTP.sys body read cannot monopolize the API beyond the upload deadline");
        Expect("408 within 15 seconds, then a complete upload succeeds");
        var (api, client) = Start(); using var server = api; using var http = client;
        using var tcp = new TcpClient();
        await tcp.ConnectAsync(IPAddress.Loopback, http.BaseAddress!.Port);
        var stream = tcp.GetStream();
        await stream.WriteAsync(Encoding.ASCII.GetBytes($"POST /transcribe HTTP/1.1\r\nHost: 127.0.0.1:{http.BaseAddress.Port}\r\nContent-Type: audio/wav\r\nContent-Length: 46\r\n\r\nR"));
        using var reader = new StreamReader(stream, leaveOpen: true);
        var status = await reader.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(15));
        Assert.Contains("408", status);
        using var request = Upload();
        AssertEvidence("next complete upload HTTP status", HttpStatusCode.OK, (await http.SendAsync(request)).StatusCode);
        Pass("stalled read timed out and admission recovered without waiting for client disconnect");
    }

    [Fact]
    public async Task ShutdownDuringUpload_IsBoundedAndRepeatable()
    {
        Setup("A raw upload stalls after one body byte while health remains available");
        Intent("Synchronous app shutdown must cancel a pending HTTP.sys read");
        Expect("Dispose completes within five seconds and a second Dispose is harmless");
        var (api, client) = Start(); using var server = api; using var http = client;
        using var tcp = new TcpClient();
        await tcp.ConnectAsync(IPAddress.Loopback, http.BaseAddress!.Port);
        await tcp.GetStream().WriteAsync(Encoding.ASCII.GetBytes($"POST /transcribe HTTP/1.1\r\nHost: 127.0.0.1:{http.BaseAddress.Port}\r\nContent-Type: audio/wav\r\nContent-Length: 46\r\n\r\nR"));
        // A health response proves the accept loop has processed the preceding upload.
        Assert.Equal(HttpStatusCode.OK, (await http.GetAsync("health")).StatusCode);
        await Task.Run(api.Dispose).WaitAsync(TimeSpan.FromSeconds(5));
        api.Dispose();
        Pass("pending body read did not block shutdown and repeated disposal was safe");
    }

    [Fact]
    public async Task ShutdownDuringInference_CancelsCallbackAndDrains()
    {
        Setup("An admitted fake inference waits indefinitely on its supplied cancellation token");
        Intent("Shutdown cancels active inference and waits for the callback to finish");
        Expect("Callback observes cancellation and Dispose completes within five seconds");
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        bool cancelled = false;
        var (api, client) = Start(async (_, ct) =>
        {
            started.SetResult();
            try { await Task.Delay(Timeout.Infinite, ct); }
            catch (OperationCanceledException) { cancelled = true; throw; }
            return new(true, "unreachable", null);
        });
        using var server = api; using var http = client; using var request = Upload();
        var response = http.SendAsync(request);
        await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await Task.Run(api.Dispose).WaitAsync(TimeSpan.FromSeconds(5));
        try { using var result = await response; } catch (HttpRequestException) { }
        AssertEvidence("callback observed cancellation", true, cancelled);
        Pass("shutdown cancelled and drained inference without blocking the caller");
    }

    [Fact]
    [Trait("Category", "LocalEmbedded")]
    public async Task InstalledEmbeddedModel_TranscribesKnownAudio_ThroughRealApi()
    {
        Setup("Explicit existing appdata GGML model and repository FirstHello.wav, no provider credentials");
        Intent("Prove actual local model loading and uploaded WAV transcription rather than a skipped/fake API pass");
        Expect("Ready health and successful recognized hello/world from real Whisper through HTTP");
        var root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));
        var model = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MarsinDictation", "models", "ggml-large-v3-turbo-q5_0.bin");
        var sample = Path.Combine(root, "windows", "MarsinDictation.Tests", "TestData", "FirstHello.wav");
        Assert.True(File.Exists(model), "this opt-in installed-model check requires the existing model");
        Assert.True(File.Exists(sample), "this opt-in installed-model check requires the known sample");
        using var whisper = new WhisperTranscriptionClient(model, "en");
        var watch = System.Diagnostics.Stopwatch.StartNew();
        whisper.LoadModel();
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => whisper.TryTranscribeAsync(Wav(), cancelled.Token));
        }
        Got("Model load milliseconds", watch.ElapsedMilliseconds);
        var wav = WavDownsampler.Downsample(await File.ReadAllBytesAsync(sample));
        Assert.True(LocalTranscriptionApi.IsNormalizedWav(wav));
        int port = FreePort();
        using var api = new LocalTranscriptionApi(whisper.TryTranscribeAsync, () => whisper.IsModelLoaded,
            true, Path.GetFileName(model), "en", "integration", port);
        Assert.True(api.TryStart());
        using var http = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{port}/"), Timeout = TimeSpan.FromMinutes(2) };
        using var request = Upload(wav);
        watch.Restart();
        var response = await http.SendAsync(request);
        Got("HTTP inference milliseconds", watch.ElapsedMilliseconds);
        AssertEvidence("inference HTTP status", HttpStatusCode.OK, response.StatusCode);
        var text = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement.GetProperty("text").GetString()!;
        AssertEvidence("contains hello", true, text.Contains("hello", StringComparison.OrdinalIgnoreCase));
        AssertEvidence("contains world", true, text.Contains("world", StringComparison.OrdinalIgnoreCase));
        // Cancel after native processing has had time to start, not just at gate admission.
        using (var interrupted = new CancellationTokenSource(TimeSpan.FromMilliseconds(100)))
        {
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => whisper.TryTranscribeAsync(wav, interrupted.Token));
            Got("in-flight native cancellation", "propagated OperationCanceledException");
        }
        // Simulate a UI-originating call followed immediately by synchronous Quit/Dispose.
        // Forwarding posts lets a regression fail an assertion instead of hanging the test host.
        var context = new ObservedCallerContext();
        var previousContext = SynchronizationContext.Current;
        Task<TranscriptionResult> desktop;
        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            desktop = whisper.TranscribeAsync(wav);
            whisper.Dispose();
        }
        finally { SynchronizationContext.SetSynchronizationContext(previousContext); }
        Assert.True((await desktop).Success);
        AssertEvidence("core continuations posted to caller UI context", 0, context.Posts);
        Assert.False(whisper.IsModelLoaded);
        Assert.Throws<ObjectDisposedException>(whisper.LoadModel);
        Assert.False((await whisper.TranscribeAsync(wav)).Success);
        Pass("real embedded Whisper produced expected words through the loopback upload API with no hosted request");
    }

    private sealed class ObservedCallerContext : SynchronizationContext
    {
        private int _posts;
        public int Posts => _posts;
        public override void Post(SendOrPostCallback callback, object? state)
        {
            Interlocked.Increment(ref _posts);
            ThreadPool.QueueUserWorkItem(_ => callback(state));
        }
    }
}

internal static class TestResponseHeaders
{
    internal static string? AccessControlAllowOrigin(this HttpResponseHeaders headers) =>
        headers.TryGetValues("Access-Control-Allow-Origin", out var values) ? values.FirstOrDefault() : null;
}

// Native Vulkan model fixtures must not overlap another test collection's model/context.
[CollectionDefinition("Local transcription API", DisableParallelization = true)]
public sealed class LocalTranscriptionApiCollection { }
