using System.IO;
using System.Net.Http;

namespace MarsinDictation.App;

public class ModelDownloader
{
    private readonly HttpClient _client;
    
    // We base the URL off the whisper.cpp HuggingFace repo
    private const string BaseUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/";

    public ModelDownloader()
    {
        _client = new HttpClient();
    }

    /// <summary>
    /// Event fired with the current bytes downloaded and the total bytes.
    /// totalBytes may be null if the server doesn't provide a Content-Length.
    /// </summary>
    public event Action<long, long?>? ProgressChanged;

    public async Task DownloadModelAsync(string modelName, string targetPath, CancellationToken ct = default)
    {
        var url = BaseUrl + modelName;

        // Ensure directory exists
        var dir = Path.GetDirectoryName(targetPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        
        response.EnsureSuccessStatusCode();

        var totalBytes = response.Content.Headers.ContentLength;
        using var responseStream = await response.Content.ReadAsStreamAsync(ct);

        // Download to a temporary file first, to avoid corrupted partial downloads
        var tempFile = targetPath + ".part";
        
        try
        {
            using var fileStream = new FileStream(tempFile, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);
            var buffer = new byte[8192];
            var totalRead = 0L;
            int read;

            while ((read = await responseStream.ReadAsync(buffer, 0, buffer.Length, ct)) > 0)
            {
                await fileStream.WriteAsync(buffer, 0, read, ct);
                totalRead += read;
                ProgressChanged?.Invoke(totalRead, totalBytes);
            }
        }
        catch (OperationCanceledException)
        {
            // Clean up partial on cancel?
            if (File.Exists(tempFile)) File.Delete(tempFile);
            throw;
        }

        // Successfully downloaded, move to final path
        if (File.Exists(targetPath))
        {
            File.Delete(targetPath);
        }
        File.Move(tempFile, targetPath);
    }
}
