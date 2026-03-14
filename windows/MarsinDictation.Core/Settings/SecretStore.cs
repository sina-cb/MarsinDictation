using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.Settings;

/// <summary>
/// DPAPI-backed secret storage for API keys and other sensitive values.
/// Secrets are encrypted per-user and stored in %LOCALAPPDATA%\MarsinDictation\secrets\
/// Each secret is a separate file named by key (e.g., "openai_api_key").
/// </summary>
public sealed class SecretStore
{
    private readonly string _secretsDir;
    private readonly ILogger<SecretStore> _logger;

    public SecretStore(ILogger<SecretStore> logger, string? secretsDir = null)
    {
        _logger = logger;
        _secretsDir = secretsDir ?? GetDefaultSecretsDir();
        Directory.CreateDirectory(_secretsDir);
    }

    /// <summary>Stores a secret value, encrypted with DPAPI (CurrentUser scope).</summary>
    public void Set(string key, string value)
    {
        try
        {
            var plainBytes = Encoding.UTF8.GetBytes(value);
            var encryptedBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
            var filePath = GetFilePath(key);
            File.WriteAllBytes(filePath, encryptedBytes);
            _logger.LogDebug("Secret stored: {Key}", key);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to store secret: {Key}", key);
            throw;
        }
    }

    /// <summary>Retrieves a secret value, decrypted with DPAPI. Returns null if not found.</summary>
    public string? Get(string key)
    {
        var filePath = GetFilePath(key);
        if (!File.Exists(filePath)) return null;

        try
        {
            var encryptedBytes = File.ReadAllBytes(filePath);
            var plainBytes = ProtectedData.Unprotect(encryptedBytes, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plainBytes);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve secret: {Key}", key);
            return null;
        }
    }

    /// <summary>Deletes a stored secret.</summary>
    public bool Delete(string key)
    {
        var filePath = GetFilePath(key);
        if (!File.Exists(filePath)) return false;

        File.Delete(filePath);
        _logger.LogDebug("Secret deleted: {Key}", key);
        return true;
    }

    /// <summary>Checks if a secret exists.</summary>
    public bool Exists(string key) => File.Exists(GetFilePath(key));

    private string GetFilePath(string key)
    {
        // Sanitize key for use as filename
        var safeName = string.Join("_", key.Split(Path.GetInvalidFileNameChars()));
        return Path.Combine(_secretsDir, safeName + ".secret");
    }

    private static string GetDefaultSecretsDir()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(appData, "MarsinDictation", "secrets");
    }
}
