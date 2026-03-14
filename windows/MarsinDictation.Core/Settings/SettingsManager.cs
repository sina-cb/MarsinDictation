using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.Settings;

/// <summary>
/// Manages application settings. Stored as JSON in %LOCALAPPDATA%\MarsinDictation\settings.json.
/// Does NOT handle secrets — use <see cref="SecretStore"/> for API keys.
/// </summary>
public sealed class SettingsManager
{
    private readonly string _filePath;
    private readonly ILogger<SettingsManager> _logger;
    private AppSettings _settings = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public SettingsManager(ILogger<SettingsManager> logger, string? filePath = null)
    {
        _logger = logger;
        _filePath = filePath ?? GetDefaultFilePath();
    }

    /// <summary>Current settings (in-memory).</summary>
    public AppSettings Settings => _settings;

    /// <summary>Loads settings from disk, or creates defaults if no file exists.</summary>
    public void Load()
    {
        if (!File.Exists(_filePath))
        {
            _logger.LogInformation("No settings file found, using defaults");
            Save(); // Create the file with defaults
            return;
        }

        try
        {
            var json = File.ReadAllText(_filePath);
            var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
            if (settings is not null)
            {
                _settings = settings;
                _logger.LogInformation("Settings loaded from {Path}", _filePath);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load settings from {Path}, using defaults", _filePath);
            _settings = new AppSettings();
        }
    }

    /// <summary>Saves current settings to disk.</summary>
    public void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(_filePath);
            if (dir is not null) Directory.CreateDirectory(dir);

            var json = JsonSerializer.Serialize(_settings, JsonOptions);
            File.WriteAllText(_filePath, json);
            _logger.LogDebug("Settings saved to {Path}", _filePath);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to save settings to {Path}", _filePath);
        }
    }

    private static string GetDefaultFilePath()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(appData, "MarsinDictation", "settings.json");
    }
}
