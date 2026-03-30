using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;

namespace MarsinDictation.App.Tray;

/// <summary>
/// Manages the system tray icon and its context menu.
/// Uses H.NotifyIcon.Wpf for WPF tray support.
/// </summary>
public sealed class TrayController : IDisposable
{
    private TaskbarIcon? _trayIcon;
    private readonly Action _onSettingsClicked;
    private readonly Action _onCleanDataClicked;
    private readonly Action _onOpenDataClicked;
    private readonly Action _onQuitClicked;
    private bool _disposed;

    public TrayController(Action onSettingsClicked, Action onCleanDataClicked, Action onOpenDataClicked, Action onQuitClicked)
    {
        _onSettingsClicked = onSettingsClicked;
        _onCleanDataClicked = onCleanDataClicked;
        _onOpenDataClicked = onOpenDataClicked;
        _onQuitClicked = onQuitClicked;
    }

    /// <summary>Creates and shows the tray icon with context menu.</summary>
    public void Initialize()
    {
        var menu = new ContextMenu();

        var settingsItem = new MenuItem { Header = "Settings" };
        settingsItem.Click += (_, _) => _onSettingsClicked();
        menu.Items.Add(settingsItem);

        var historyItem = new MenuItem { Header = "History (coming soon)", IsEnabled = false };
        historyItem.Click += (_, _) => { /* Phase 5: open history panel */ };
        menu.Items.Add(historyItem);

        menu.Items.Add(new Separator());

        var openDataItem = new MenuItem { Header = "Open User Data Folder" };
        openDataItem.Click += (_, _) => _onOpenDataClicked();
        menu.Items.Add(openDataItem);

        var cleanItem = new MenuItem { Header = "Clean User Data..." };
        cleanItem.Click += (_, _) => _onCleanDataClicked();
        menu.Items.Add(cleanItem);

        menu.Items.Add(new Separator());

        var quitItem = new MenuItem { Header = "Quit" };
        quitItem.Click += (_, _) => _onQuitClicked();
        menu.Items.Add(quitItem);

        _trayIcon = new TaskbarIcon
        {
            ToolTipText = "MarsinDictation",
            ContextMenu = menu,
        };

        // Use the application icon from the system
        using var stream = typeof(TrayController).Assembly.GetManifestResourceStream("MarsinDictation.App.Assets.app-icon.ico");
        if (stream is not null)
        {
            _trayIcon.Icon = new Icon(stream);
        }
        else
        {
            // Fallback: create a simple icon programmatically
            _trayIcon.Icon = CreateDefaultIcon();
        }

        // Force the tray icon to be created and shown
        _trayIcon.ForceCreate();
    }

    private static Icon CreateDefaultIcon()
    {
        // Create a simple 16x16 icon with a microphone-like shape
        using var bmp = new Bitmap(16, 16);
        using var g = Graphics.FromImage(bmp);
        g.Clear(Color.Transparent);
        // Draw a filled circle as a simple icon
        using var brush = new SolidBrush(Color.FromArgb(0, 120, 215)); // Windows accent blue
        g.FillEllipse(brush, 2, 2, 12, 12);
        using var pen = new Pen(Color.White, 1.5f);
        // Draw a simple "M" shape
        g.DrawLine(pen, 5, 9, 5, 5);
        g.DrawLine(pen, 5, 5, 8, 7);
        g.DrawLine(pen, 8, 7, 11, 5);
        g.DrawLine(pen, 11, 5, 11, 9);

        var hIcon = bmp.GetHicon();
        return Icon.FromHandle(hIcon);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _trayIcon?.Dispose();
        _disposed = true;
    }
}
