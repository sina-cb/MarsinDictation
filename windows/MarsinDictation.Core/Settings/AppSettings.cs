namespace MarsinDictation.Core.Settings;

/// <summary>
/// Application settings. Serialized to JSON.
/// Secrets (API keys) are NOT stored here — they use SecretStore (DPAPI).
/// </summary>
public sealed class AppSettings
{
    public string TranscriptionProvider { get; set; } = "openai";
    public string OpenAIModel { get; set; } = "gpt-4o-mini-transcribe";
    public string LocalAIEndpoint { get; set; } = "http://localhost:3850";
    public string LocalAIModel { get; set; } = "whisper-1";
    public string Language { get; set; } = "en";
    public bool AutoPunctuation { get; set; } = true;
    public bool StripFillerWords { get; set; } = true;
    public bool LaunchAtStartup { get; set; } = false;
    public bool LocalHistory { get; set; } = true;
}
