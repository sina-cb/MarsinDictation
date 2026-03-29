using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using System.Runtime.InteropServices;

namespace MarsinDictation.App;

/// <summary>
/// Borderless toast-style popup. Hidden by default.
/// Appears at bottom-center (~10% up from bottom) when triggered.
/// Uses Win32 MonitorFromWindow to always target the primary monitor,
/// even after HDMI hot-plug/unplug events.
/// </summary>
public partial class StatusWindow : Window
{
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int GWL_EXSTYLE = -20;

    private const int MONITOR_DEFAULTTOPRIMARY = 0x00000001;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    private readonly DispatcherTimer _hideTimer;

    public StatusWindow()
    {
        InitializeComponent();

        _hideTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _hideTimer.Tick += (_, _) =>
        {
            _hideTimer.Stop();
            this.Visibility = Visibility.Hidden;
        };

        // Position: bottom-center, ~10% up from the bottom of the screen
        Loaded += (_, _) => PositionWindow();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new WindowInteropHelper(this).Handle;
        var extendedStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, extendedStyle | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
    }

    private void PositionWindow()
    {
        // Query the primary monitor's work area via Win32 (immune to WPF caching issues)
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd != IntPtr.Zero)
        {
            var hMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
            var mi = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
            if (GetMonitorInfo(hMonitor, ref mi))
            {
                // Get DPI scaling factor for this window
                var source = PresentationSource.FromVisual(this);
                double dpiScaleX = source?.CompositionTarget?.TransformFromDevice.M11 ?? 1.0;
                double dpiScaleY = source?.CompositionTarget?.TransformFromDevice.M22 ?? 1.0;

                // Convert physical pixels to WPF device-independent units
                double workLeft = mi.rcWork.Left * dpiScaleX;
                double workTop = mi.rcWork.Top * dpiScaleY;
                double workWidth = (mi.rcWork.Right - mi.rcWork.Left) * dpiScaleX;
                double workHeight = (mi.rcWork.Bottom - mi.rcWork.Top) * dpiScaleY;

                Left = workLeft + (workWidth - ActualWidth) / 2;
                Top = workTop + workHeight - (workHeight * 0.10) - ActualHeight;
                return;
            }
        }

        // Fallback: use WPF SystemParameters if Win32 call fails
        var workArea = SystemParameters.WorkArea;
        Left = (workArea.Width - ActualWidth) / 2 + workArea.Left;
        Top = workArea.Bottom - (workArea.Height * 0.10) - ActualHeight;
    }

    public void ShowToast(string text, ToastType type, double durationSeconds = 2.0)
    {
        Dispatcher.Invoke(() =>
        {
            StatusText.Text = text;
            StatusDot.Fill = type switch
            {
                ToastType.Recording => new SolidColorBrush(Color.FromRgb(0xF3, 0x8B, 0xA8)),
                ToastType.Playing => new SolidColorBrush(Color.FromRgb(0x89, 0xB4, 0xFA)),
                _ => new SolidColorBrush(Color.FromRgb(0x4C, 0xAF, 0x50)),
            };

            this.Visibility = Visibility.Visible;
            PositionWindow();

            _hideTimer.Stop();
            if (type == ToastType.Recording)
            {
                // Recording stays visible until stopped
            }
            else
            {
                _hideTimer.Interval = TimeSpan.FromSeconds(durationSeconds);
                _hideTimer.Start();
            }
        });
    }

    public void HideToast()
    {
        Dispatcher.Invoke(() =>
        {
            _hideTimer.Stop();
            this.Visibility = Visibility.Hidden;
        });
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        _hideTimer.Stop();
        base.OnClosing(e);
    }
}

public enum ToastType
{
    Idle,
    Recording,
    Playing
}
