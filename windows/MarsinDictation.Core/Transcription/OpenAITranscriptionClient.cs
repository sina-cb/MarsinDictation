using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.Transcription;

/// <summary>
/// OpenAI-compatible transcription client.
/// Sends WAV audio to POST /v1/audio/transcriptions (multipart/form-data).
/// Works with both OpenAI and LocalAI — parameterized by base URL, auth, and model.
/// </summary>
public sealed class OpenAITranscriptionClient : ITranscriptionClient, IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly string _model;
    private readonly ILogger<OpenAITranscriptionClient> _logger;
    private readonly bool _ownsClient;

    /// <summary>
    /// Creates a client for OpenAI-compatible transcription.
    /// </summary>
    /// <param name="logger">Logger instance.</param>
    /// <param name="baseUrl">API base URL (e.g., "https://api.openai.com" or "http://localhost:8080").</param>
    /// <param name="apiKey">Bearer token for auth. Pass null or empty for no-auth (LocalAI).</param>
    /// <param name="model">Model name (e.g., "gpt-4o-mini-transcribe", "whisper-1").</param>
    /// <param name="httpClient">Optional HttpClient for testing.</param>
    public OpenAITranscriptionClient(
        ILogger<OpenAITranscriptionClient> logger,
        string baseUrl,
        string? apiKey,
        string model,
        HttpClient? httpClient = null)
    {
        _logger = logger;
        _model = model;

        if (httpClient != null)
        {
            _httpClient = httpClient;
            _ownsClient = false;
        }
        else
        {
            _httpClient = new HttpClient
            {
                BaseAddress = new Uri(baseUrl.TrimEnd('/')),
                Timeout = TimeSpan.FromMinutes(5)
            };
            _ownsClient = true;
        }

        if (!string.IsNullOrEmpty(apiKey))
        {
            _httpClient.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", apiKey);
        }
    }

    public async Task<TranscriptionResult> TranscribeAsync(byte[] wavData, CancellationToken ct = default)
    {
        try
        {
            _logger.LogInformation("Transcribing {Bytes} bytes with model {Model}", wavData.Length, _model);

            using var content = new MultipartFormDataContent();

            var fileContent = new ByteArrayContent(wavData);
            fileContent.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
            content.Add(fileContent, "file", "audio.wav");
            content.Add(new StringContent(_model), "model");

            var response = await _httpClient.PostAsync("/v1/audio/transcriptions", content, ct);

            if (!response.IsSuccessStatusCode)
            {
                var errorBody = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning("Transcription failed: {Status} — {Body}",
                    response.StatusCode, errorBody);
                return new TranscriptionResult(false, null,
                    $"HTTP {(int)response.StatusCode}: {errorBody}");
            }

            var json = await response.Content.ReadAsStringAsync(ct);
            _logger.LogDebug("Transcription response: {Json}", json);

            // OpenAI returns { "text": "..." }
            using var doc = JsonDocument.Parse(json);
            var text = doc.RootElement.GetProperty("text").GetString();

            if (string.IsNullOrWhiteSpace(text))
            {
                _logger.LogInformation("Transcription returned empty text");
                return new TranscriptionResult(true, "[no audio]", null);
            }

            _logger.LogInformation("Transcription result: \"{Text}\"", text);
            return new TranscriptionResult(true, text.Trim(), null);
        }
        catch (TaskCanceledException) when (ct.IsCancellationRequested)
        {
            return new TranscriptionResult(false, null, "Transcription cancelled");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Transcription failed");
            return new TranscriptionResult(false, null, ex.Message);
        }
    }

    public void Dispose()
    {
        if (_ownsClient)
            _httpClient.Dispose();
    }
}
