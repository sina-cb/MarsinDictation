namespace MarsinDictation.Core.Settings;

/// <summary>
/// Loads .env files and sets environment variables.
/// Called once at app startup to populate OPENAI_API_KEY, etc.
/// </summary>
public static class EnvLoader
{
    /// <summary>
    /// Loads a .env file and sets each KEY=VALUE as an environment variable.
    /// Ignores blank lines, comments (#), and lines without '='.
    /// Does NOT override existing environment variables.
    /// </summary>
    public static void Load(string filePath)
    {
        if (!File.Exists(filePath)) return;

        foreach (var rawLine in File.ReadAllLines(filePath))
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line.StartsWith('#')) continue;

            var eqIndex = line.IndexOf('=');
            if (eqIndex <= 0) continue;

            var key = line[..eqIndex].Trim();
            var value = line[(eqIndex + 1)..].Trim();

            // Don't override existing env vars (system-level takes precedence)
            if (Environment.GetEnvironmentVariable(key) == null)
            {
                Environment.SetEnvironmentVariable(key, value);
            }
        }
    }
}
