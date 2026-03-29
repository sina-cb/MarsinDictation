using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Extensions.Logging;
using MarsinDictation.App.Tray;
using MarsinDictation.Core;
using MarsinDictation.Core.Audio;
using MarsinDictation.Core.Hotkey;
using MarsinDictation.Core.History;
using MarsinDictation.Core.Settings;
using MarsinDictation.Core.Transcription;

namespace MarsinDictation.App;

/// <summary>
/// Application entry point.
/// Three recording modes:
///   - Ctrl+Win HOLD:    record while held, stop + transcribe on release
///   - Ctrl+Shift+Space: toggle recording on/off
///   - Alt+Shift+Z:      recovery paste
/// </summary>
public partial class App : Application
{
    private StatusWindow? _statusWindow;
    private MainWindow? _mainWindow;
    private TrayController? _trayController;
    private HotkeyManager? _hotkeyManager;
    private DictationService? _dictationService;
    private AudioRecorder? _audioRecorder;
    private AudioPlayer? _audioPlayer;
    private TranscriptStore? _transcriptStore;
    private SettingsManager? _settingsManager;
    private ILoggerFactory? _loggerFactory;
    private ITranscriptionClient? _transcriptionClient;
    private MarsinDictation.Core.Injection.SendInputInjector? _injector;
    private string? _lastTranscription;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Load .env — check multiple locations (dev repo, CWD, installed location)
        var envPath = System.IO.Path.Combine(
            System.IO.Directory.GetCurrentDirectory(), "..", ".env");
        EnvLoader.Load(System.IO.Path.GetFullPath(envPath));
        EnvLoader.Load(System.IO.Path.Combine(
            System.IO.Directory.GetCurrentDirectory(), ".env"));
        EnvLoader.Load(System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MarsinDictation", ".env"));

        // Log file: %LOCALAPPDATA%/MarsinDictation/logs/app.log (truncated each launch)
        var logDir = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MarsinDictation", "logs");
        var logFile = System.IO.Path.Combine(logDir, "app.log");

        _loggerFactory = LoggerFactory.Create(builder =>
        {
            builder.SetMinimumLevel(LogLevel.Debug);
            builder.AddDebug();
            builder.AddProvider(new MarsinDictation.Core.Logging.FileLoggerProvider(logFile));
        });

        var logger = _loggerFactory.CreateLogger<App>();
        logger.LogInformation("MarsinDictation starting");

        // Initialize transcription client from .env config
        var provider = Environment.GetEnvironmentVariable("MARSIN_TRANSCRIPTION_PROVIDER") ?? "localai";
        if (provider == "openai")
        {
            var apiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY");
            var model = Environment.GetEnvironmentVariable("OPENAI_MODEL") ?? "gpt-4o-mini-transcribe";
            if (!string.IsNullOrEmpty(apiKey))
            {
                _transcriptionClient = new OpenAITranscriptionClient(
                    _loggerFactory.CreateLogger<OpenAITranscriptionClient>(),
                    "https://api.openai.com", apiKey, model);
                logger.LogInformation("Transcription: OpenAI ({Model})", model);
            }
            else
            {
                logger.LogWarning("OPENAI_API_KEY not set — transcription disabled");
            }
        }
        else
        {
            var endpoint = Environment.GetEnvironmentVariable("LOCALAI_ENDPOINT") ?? "http://localhost:3850";
            var model = Environment.GetEnvironmentVariable("LOCALAI_MODEL") ?? "whisper-1";
            _transcriptionClient = new OpenAITranscriptionClient(
                _loggerFactory.CreateLogger<OpenAITranscriptionClient>(),
                endpoint, null, model);
            logger.LogInformation("Transcription: LocalAI ({Endpoint}, {Model})", endpoint, model);
        }

        // Initialize core services
        _settingsManager = new SettingsManager(_loggerFactory.CreateLogger<SettingsManager>());
        _settingsManager.Load();

        _transcriptStore = new TranscriptStore(_loggerFactory.CreateLogger<TranscriptStore>());
        _transcriptStore.Load();

        _dictationService = new DictationService(_loggerFactory.CreateLogger<DictationService>());
        _audioRecorder = new AudioRecorder(_loggerFactory.CreateLogger<AudioRecorder>());
        _audioPlayer = new AudioPlayer(_loggerFactory.CreateLogger<AudioPlayer>());

        _hotkeyManager = new HotkeyManager(_loggerFactory.CreateLogger<HotkeyManager>());
        _hotkeyManager.RecordingStarted += OnHoldRecordStart;
        _hotkeyManager.RecordingStopped += OnHoldRecordStop;
        _hotkeyManager.RecoveryHotkeyPressed += OnRecoveryPressed;

        // Create the toast window (hidden)
        _statusWindow = new StatusWindow();
        _statusWindow.Show();
        _statusWindow.Visibility = Visibility.Hidden;

        var helper = new System.Windows.Interop.WindowInteropHelper(_statusWindow);
        var hwnd = helper.Handle;

        var source = System.Windows.Interop.HwndSource.FromHwnd(hwnd);
        source?.AddHook((IntPtr h, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
        {
            const int WM_HOTKEY = 0x0312;
            if (msg == WM_HOTKEY)
            {
                handled = _hotkeyManager.ProcessHotkeyMessage(wParam.ToInt32());
            }
            return IntPtr.Zero;
        });

        try
        {
            _hotkeyManager.Register(hwnd);
            logger.LogInformation("Hotkeys registered");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to register hotkeys");
        }

        _mainWindow = new MainWindow();

        _trayController = new TrayController(
            onSettingsClicked: () => { _mainWindow.Show(); _mainWindow.Activate(); },
            onCleanDataClicked: OnCleanDataClicked,
            onOpenDataClicked: OnOpenDataClicked,
            onQuitClicked: () => { logger.LogInformation("Quit from tray"); DoShutdown(); }
        );
        _trayController.Initialize();

        // Text injection via SendInput (Unicode keystrokes)
        _injector = new MarsinDictation.Core.Injection.SendInputInjector(
            _loggerFactory.CreateLogger<MarsinDictation.Core.Injection.SendInputInjector>());
        logger.LogInformation("Text injector ready");

        logger.LogInformation("Ready — Ctrl+Win (hold) = record, Alt+Shift+Z = recovery");
    }

    // ── Hold-to-record (Ctrl+Win) ─────────────────────────────

    private void OnHoldRecordStart()
    {
        if (_audioRecorder!.IsRecording) return;
        Dispatcher.Invoke(() =>
        {
            _audioRecorder.Start();
            _statusWindow?.ShowToast("🔴 Recording...", ToastType.Recording);
        });
    }

    private void OnHoldRecordStop()
    {
        if (!_audioRecorder!.IsRecording) return;
        Dispatcher.Invoke(async () =>
        {
            var wavData = _audioRecorder.Stop();

            if (wavData == null || wavData.Length <= 44)
            {
                _statusWindow?.ShowToast("⚠ No audio recorded", ToastType.Idle, 1.5);
                return;
            }

            if (_transcriptionClient != null)
            {
                _statusWindow?.ShowToast("⏳ Transcribing...", ToastType.Playing, 30.0);
                try
                {
                    // Downsample to 16kHz/16-bit/mono before uploading
                    var dsLogger = _loggerFactory!.CreateLogger("WavDownsampler");
                    var optimizedWav = MarsinDictation.Core.Audio.WavDownsampler.Downsample(wavData, dsLogger);

                    var result = await _transcriptionClient.TranscribeAsync(optimizedWav);

                    if (result.Success)
                    {
                        _loggerFactory!.CreateLogger<App>()
                            .LogInformation("📝 Transcription: \"{Text}\"", result.Text);
                        _lastTranscription = result.Text;
                        DoInjectText(result.Text!);
                    }
                    else
                    {
                        _loggerFactory!.CreateLogger<App>()
                            .LogWarning("Transcription failed: {Error}", result.Error);
                        _statusWindow?.ShowToast("⚠ Transcription failed", ToastType.Idle, 3.0);
                    }
                }
                catch (Exception ex)
                {
                    _loggerFactory!.CreateLogger<App>()
                        .LogError(ex, "Transcription/injection pipeline error");
                    _statusWindow?.ShowToast("⚠ Error — use Alt+Shift+Z to recover", ToastType.Idle, 4.0);
                }
            }
            else
            {
                _statusWindow?.ShowToast("🔊 Playing back (no API key)...", ToastType.Playing, 3.0);
                _audioPlayer!.Play(wavData, () =>
                    Dispatcher.Invoke(() =>
                        _statusWindow?.ShowToast("✅ Done", ToastType.Idle, 1.5)));
                _lastTranscription = null;
            }
        });
    }

    // ── Shared injection ────────────────────────────────────────

    private void DoInjectText(string text)
    {
        var logger = _loggerFactory!.CreateLogger<App>();
        bool injected = _injector?.TryInjectText(text) ?? false;

        var state = injected ? TranscriptState.Success : TranscriptState.Pending;
        var currentProvider = Environment.GetEnvironmentVariable("MARSIN_TRANSCRIPTION_PROVIDER") ?? "localai";
        var currentModel = currentProvider == "openai"
            ? Environment.GetEnvironmentVariable("OPENAI_MODEL") ?? "gpt-4o-mini-transcribe"
            : Environment.GetEnvironmentVariable("LOCALAI_MODEL") ?? "whisper-large-turbo";
        var entry = TranscriptEntry.Create(text, currentProvider, currentModel, state);
        _transcriptStore?.Add(entry);

        if (injected)
        {
            _statusWindow?.ShowToast("✔ Injected", ToastType.Idle, 1.5);
        }
        else
        {
            // Only touch clipboard as a last-resort fallback when injection fails
            try { System.Windows.Clipboard.SetText(text); } catch { /* clipboard locked */ }
            logger.LogWarning("Injection failed — copied to clipboard");
            _statusWindow?.ShowToast("📋 Copied to clipboard (Ctrl+V)", ToastType.Idle, 3.0);
        }
    }

    // ── Recovery (Alt+Shift+Z) ───────────────────────────────

    private void OnRecoveryPressed()
    {
        Dispatcher.Invoke(async () =>
        {
            var logger = _loggerFactory!.CreateLogger<App>();

            if (string.IsNullOrEmpty(_lastTranscription))
            {
                logger.LogWarning("Recovery: no transcription available");
                _statusWindow?.ShowToast("⚠ No text to recover", ToastType.Idle, 2.0);
                return;
            }

            logger.LogInformation("Recovery: \"{Text}\"", _lastTranscription);

            // Wait for user to release Alt+Shift+Z keys before injecting
            await Task.Delay(200);
            DoInjectText(_lastTranscription);
        });
    }

    // ── User data management ─────────────────────────────────

    private void OnOpenDataClicked()
    {
        var appDataDir = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MarsinDictation");
            
        if (System.IO.Directory.Exists(appDataDir))
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = appDataDir,
                UseShellExecute = true
            });
        }
    }

    private void OnCleanDataClicked()
    {
        var appDataDir = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MarsinDictation");

        var result = System.Windows.MessageBox.Show(
            $"This will permanently delete all user data from:\n{appDataDir}\n\nThis includes:\n• All transcripts history (JSONL)\n• Log files\n• Settings\n• Any cached data\n\nAre you sure you want to proceed?",
            "Clean User Data",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.Yes) return;

        var logger = _loggerFactory!.CreateLogger<App>();

        try
        {
            // Clear in-memory transcript store
            _transcriptStore?.Clear();

            // Delete everything in the app data directory
            if (System.IO.Directory.Exists(appDataDir))
            {
                foreach (var file in System.IO.Directory.GetFiles(appDataDir, "*", System.IO.SearchOption.AllDirectories))
                {
                    try { System.IO.File.Delete(file); } catch { }
                }
                foreach (var dir in System.IO.Directory.GetDirectories(appDataDir))
                {
                    try { System.IO.Directory.Delete(dir, true); } catch { }
                }
            }

            logger.LogInformation("User data cleaned: {Dir}", appDataDir);
            _statusWindow?.ShowToast("🧹 User data cleaned", ToastType.Idle, 2.0);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to clean user data");
            _statusWindow?.ShowToast("⚠ Clean failed", ToastType.Idle, 3.0);
        }
    }

    private void DoShutdown()
    {
        _audioRecorder?.Dispose();
        _audioPlayer?.Dispose();
        _hotkeyManager?.Dispose();
        _trayController?.Dispose();
        (_transcriptionClient as IDisposable)?.Dispose();
        _statusWindow?.Close();
        _loggerFactory?.Dispose();
        Shutdown();
    }
}
