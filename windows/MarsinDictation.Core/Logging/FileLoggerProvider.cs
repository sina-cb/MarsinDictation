using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.Logging;

/// <summary>
/// Simple file logger that appends timestamped log lines to a file.
/// Used to stream app logs to deploy.py --hold via file tailing.
/// </summary>
public sealed class FileLoggerProvider : ILoggerProvider
{
    private readonly StreamWriter _writer;
    private readonly object _lock = new();

    public FileLoggerProvider(string filePath)
    {
        var dir = Path.GetDirectoryName(filePath);
        if (dir != null) Directory.CreateDirectory(dir);

        // Truncate on startup (fresh log each run)
        _writer = new StreamWriter(filePath, append: false) { AutoFlush = true };
    }

    public ILogger CreateLogger(string categoryName) => new FileLogger(categoryName, this);
    public void Dispose() => _writer.Dispose();

    internal void Write(string message)
    {
        lock (_lock)
        {
            _writer.WriteLine(message);
        }
    }
}

internal sealed class FileLogger : ILogger
{
    private readonly string _category;
    private readonly FileLoggerProvider _provider;

    public FileLogger(string category, FileLoggerProvider provider)
    {
        // Use short category name (last segment)
        var dot = category.LastIndexOf('.');
        _category = dot >= 0 ? category[(dot + 1)..] : category;
        _provider = provider;
    }

    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Debug;

    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
    {
        if (!IsEnabled(logLevel)) return;

        var level = logLevel switch
        {
            LogLevel.Trace => "TRC",
            LogLevel.Debug => "DBG",
            LogLevel.Information => "INF",
            LogLevel.Warning => "WRN",
            LogLevel.Error => "ERR",
            LogLevel.Critical => "CRT",
            _ => "???"
        };

        var ts = DateTime.Now.ToString("HH:mm:ss.fff");
        var msg = formatter(state, exception);
        _provider.Write($"{ts} [{level}] {_category}: {msg}");

        if (exception != null)
            _provider.Write($"  {exception}");
    }
}
