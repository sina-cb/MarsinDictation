using System.Buffers.Binary;
using System.Net;
using System.Text.Json;
using MarsinDictation.Core.Transcription;

namespace MarsinDictation.Core.Api;

/// <summary>
/// Loopback-only, upload-only embedded transcription. No filesystem or desktop injection API.
/// Browser requests are rejected; callers upload normalized PCM WAV rather than a path.
/// Only one API request is admitted, and the client shares its inference gate with hotkeys.
/// </summary>
public sealed class LocalTranscriptionApi : IDisposable
{
    public const int DefaultPort = 6976;
    public const int MaxBodyBytes = 4 * 1024 * 1024;
    private readonly HttpListener _listener = new();
    private readonly CancellationTokenSource _shutdown = new();
    private readonly Func<byte[], CancellationToken, Task<TranscriptionResult?>> _transcribe;
    private readonly Func<bool> _ready;
    private readonly bool _modelAvailable;
    private readonly string _model;
    private readonly string _language;
    private readonly string _version;
    private readonly int _port;
    private Task? _loop;
    private Task? _active;
    private int _busy;

    public LocalTranscriptionApi(
        Func<byte[], CancellationToken, Task<TranscriptionResult?>> transcribe,
        Func<bool> ready, bool modelAvailable, string model, string language, string version,
        int port = DefaultPort)
    {
        _transcribe = transcribe;
        _ready = ready;
        _modelAvailable = modelAvailable;
        _model = Path.GetFileName(model);
        _language = language;
        _version = version;
        _port = port;
        _listener.Prefixes.Add($"http://127.0.0.1:{port}/");
    }

    // A collision/access failure leaves dictation running. The caller reports availability.
    public bool TryStart()
    {
        try { _listener.Start(); }
        catch (HttpListenerException) { _listener.Close(); return false; }
        _loop = Task.Run(AcceptAsync);
        return true;
    }

    private object Metadata(bool ready, string? reason = null) => new
    {
        service = "marsin-dictation", apiVersion = 1, version = _version,
        backend = "embedded-whisper", model = _model, language = _language, ready, reason
    };

    private async Task AcceptAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            HttpListenerContext context;
            try { context = await _listener.GetContextAsync(); }
            catch (Exception ex) when (ex is HttpListenerException or ObjectDisposedException) { break; }
            try
            {
                var req = context.Request;
                // Explicit Host and browser-header checks also prevent DNS rebinding/CSRF.
                if (req.RemoteEndPoint is null || !IPAddress.IsLoopback(req.RemoteEndPoint.Address)
                    || req.Headers["Host"] != $"127.0.0.1:{_port}"
                    || req.Headers["Origin"] != null
                    || (req.Headers["Sec-Fetch-Site"] is string site && site != "none"))
                { await Reply(context, 403, new { error = "local_client_required" }); continue; }

                if (req.Url?.AbsolutePath == "/health" && req.HttpMethod == "GET")
                {
                    bool ready = _ready();
                    await Reply(context, ready ? 200 : 503,
                        Metadata(ready, ready ? null : _modelAvailable ? "model_loading_or_failed" : "model_missing"));
                    continue;
                }
                if (req.Url?.AbsolutePath != "/transcribe")
                { await Reply(context, 404, new { error = "not_found" }); continue; }
                if (req.HttpMethod != "POST")
                { await Reply(context, 405, new { error = "post_required" }); continue; }
                if (req.ContentType?.Split(';')[0].Trim().ToLowerInvariant() != "audio/wav")
                { await Reply(context, 415, new { error = "audio_wav_required" }); continue; }
                if (req.ContentLength64 < 0)
                { await Reply(context, 411, new { error = "content_length_required" }); continue; }
                if (req.ContentLength64 > MaxBodyBytes)
                { await Reply(context, 413, new { error = "audio_too_large" }); continue; }
                if (!_modelAvailable || !_ready())
                { await Reply(context, 503, new { error = "embedded_model_not_ready" }); continue; }
                if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0)
                { await Reply(context, 429, new { error = "transcription_busy" }); continue; }

                _active = Task.Run(() => TranscribeAsync(context));
            }
            catch { context.Response.Abort(); }
        }
    }

    private async Task TranscribeAsync(HttpListenerContext context)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_shutdown.Token);
        deadline.CancelAfter(TimeSpan.FromMinutes(2));
        try
        {
            var request = context.Request;
            using var readDeadline = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token);
            readDeadline.CancelAfter(TimeSpan.FromSeconds(10));
            // Content-Length was checked before allocation. Read exactly it, never an unbounded stream.
            var wav = new byte[(int)request.ContentLength64];
            await request.InputStream.ReadExactlyAsync(wav, readDeadline.Token);
            if (!IsNormalizedWav(wav))
            { await Reply(context, 400, new { error = "pcm16_mono_16000_wav_required" }); return; }
            var result = await _transcribe(wav, deadline.Token);
            if (result is null)
            { await Reply(context, 429, new { error = "transcription_busy" }); return; }
            if (!result.Success)
            { await Reply(context, 503, new { error = "embedded_transcription_failed" }); return; }
            if (string.IsNullOrWhiteSpace(result.Text) || result.Text == "[no audio]")
            { await Reply(context, 422, new { error = "no_speech_recognized" }); return; }
            await Reply(context, 200, new
            {
                text = result.Text, backend = "embedded-whisper", model = _model,
                language = _language, version = _version
            });
        }
        catch (OperationCanceledException)
        { await Reply(context, 408, new { error = "transcription_timeout_or_shutdown" }); }
        catch (EndOfStreamException)
        { await Reply(context, 400, new { error = "incomplete_audio" }); }
        catch
        { await Reply(context, 503, new { error = "embedded_transcription_failed" }); }
        finally
        {
            try { context.Response.Close(); } catch { }
            Interlocked.Exchange(ref _busy, 0);
        }
    }

    public static bool IsNormalizedWav(ReadOnlySpan<byte> wav)
    {
        if (wav.Length < 44 || wav.Length > MaxBodyBytes
            || !wav[..4].SequenceEqual("RIFF"u8) || !wav.Slice(8, 4).SequenceEqual("WAVE"u8)
            || BinaryPrimitives.ReadUInt32LittleEndian(wav.Slice(4, 4)) != wav.Length - 8) return false;
        bool format = false, data = false;
        int position = 12;
        while (position <= wav.Length - 8)
        {
            var id = wav.Slice(position, 4);
            uint length = BinaryPrimitives.ReadUInt32LittleEndian(wav.Slice(position + 4, 4));
            position += 8;
            if (length > wav.Length - position) return false;
            if (id.SequenceEqual("fmt "u8))
            {
                if (format || length < 16) return false;
                var fmt = wav.Slice(position, 16);
                if (BinaryPrimitives.ReadUInt16LittleEndian(fmt) != 1
                    || BinaryPrimitives.ReadUInt16LittleEndian(fmt[2..]) != 1
                    || BinaryPrimitives.ReadUInt32LittleEndian(fmt[4..]) != 16000
                    || BinaryPrimitives.ReadUInt32LittleEndian(fmt[8..]) != 32000
                    || BinaryPrimitives.ReadUInt16LittleEndian(fmt[12..]) != 2
                    || BinaryPrimitives.ReadUInt16LittleEndian(fmt[14..]) != 16) return false;
                format = true;
            }
            if (id.SequenceEqual("data"u8))
            {
                if (!format || data || length == 0 || length % 2 != 0 || length > 120 * 32000) return false;
                data = true;
            }
            position += (int)length + (int)(length % 2);
        }
        return format && data && position == wav.Length;
    }

    private static async Task Reply(HttpListenerContext context, int status, object body)
    {
        try
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(body);
            context.Response.StatusCode = status;
            context.Response.ContentType = "application/json; charset=utf-8";
            context.Response.Headers["Cache-Control"] = "no-store";
            context.Response.Headers["X-Content-Type-Options"] = "nosniff";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes);
            context.Response.Close();
        }
        catch { context.Response.Abort(); }
    }

    public void Dispose()
    {
        _shutdown.Cancel();
        _listener.Close();
        try { _loop?.GetAwaiter().GetResult(); _active?.GetAwaiter().GetResult(); } catch { }
        _shutdown.Dispose();
    }
}
