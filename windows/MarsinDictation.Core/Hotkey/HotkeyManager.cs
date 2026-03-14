using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.Hotkey;

/// <summary>
/// Two hotkeys via WH_KEYBOARD_LL:
///   - Ctrl+Win (hold):  record while held, stop on release
///   - Alt+Shift+Z:      recovery paste
/// </summary>
public sealed class HotkeyManager : IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;

    private const int VK_LCONTROL = 0xA2;
    private const int VK_RCONTROL = 0xA3;
    private const int VK_CONTROL = 0x11;
    private const int VK_LSHIFT = 0xA0;
    private const int VK_RSHIFT = 0xA1;
    private const int VK_SHIFT_KEY = 0x10;
    private const int VK_LALT = 0xA4;
    private const int VK_RALT = 0xA5;
    private const int VK_MENU = 0x12;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;
    private const int VK_Z_KEY = 0x5A;

    private readonly ILogger<HotkeyManager> _logger;
    private IntPtr _hookHandle;
    private LowLevelKeyboardProc? _hookProc;
    private bool _registered;
    private bool _disposed;

    // Modifier tracking
    private bool _ctrlHeld;
    private bool _shiftHeld;
    private bool _altHeld;
    private bool _winHeld;

    // Hold-to-record state
    private bool _isHoldRecording;
    private bool _otherKeyPressed;

    public HotkeyManager(ILogger<HotkeyManager> logger)
    {
        _logger = logger;
    }

    /// <summary>Fired when Ctrl+Win are both held down.</summary>
    public event Action? RecordingStarted;
    /// <summary>Fired when Ctrl+Win are released after hold-recording.</summary>
    public event Action? RecordingStopped;
    /// <summary>Fired when Alt+Shift+Z is pressed.</summary>
    public event Action? RecoveryHotkeyPressed;

    public void Register(IntPtr hwnd)
    {
        if (_registered)
            throw new InvalidOperationException("Already registered.");

        _hookProc = LowLevelKeyboardCallback;
        _hookHandle = SetWindowsHookEx(WH_KEYBOARD_LL, _hookProc, IntPtr.Zero, 0);
        if (_hookHandle == IntPtr.Zero)
        {
            var error = Marshal.GetLastWin32Error();
            throw new Win32Exception(error, "Failed to install keyboard hook.");
        }

        _registered = true;
        _logger.LogInformation("Keyboard hook installed");
        _logger.LogInformation("  Ctrl+Win (hold)   = record while held");
        _logger.LogInformation("  Alt+Shift+Z       = recovery paste");
    }

    private IntPtr LowLevelKeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int vkCode = Marshal.ReadInt32(lParam);
            int msg = wParam.ToInt32();
            bool isDown = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
            bool isUp = msg == WM_KEYUP || msg == WM_SYSKEYUP;

            bool isCtrl = vkCode == VK_LCONTROL || vkCode == VK_RCONTROL || vkCode == VK_CONTROL;
            bool isShift = vkCode == VK_LSHIFT || vkCode == VK_RSHIFT || vkCode == VK_SHIFT_KEY;
            bool isAlt = vkCode == VK_LALT || vkCode == VK_RALT || vkCode == VK_MENU;
            bool isWin = vkCode == VK_LWIN || vkCode == VK_RWIN;
            bool isZ = vkCode == VK_Z_KEY;

            if (isDown)
            {
                if (isCtrl) _ctrlHeld = true;
                else if (isShift) _shiftHeld = true;
                else if (isAlt) _altHeld = true;
                else if (isWin) _winHeld = true;

                // Alt+Shift+Z → recovery
                else if (isZ && _altHeld && _shiftHeld && !_ctrlHeld)
                {
                    _logger.LogInformation(">>> Recovery (Alt+Shift+Z)");
                    RecoveryHotkeyPressed?.Invoke();
                    return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
                }

                // Any other non-modifier key → cancel hold
                else
                {
                    _otherKeyPressed = true;
                    if (_isHoldRecording)
                    {
                        _isHoldRecording = false;
                        _logger.LogInformation("Hold cancelled — other key pressed");
                        RecordingStopped?.Invoke();
                    }
                }

                // Start hold-recording when Ctrl+Win both held, no other key
                if (_ctrlHeld && _winHeld && !_altHeld && !_otherKeyPressed && !_isHoldRecording)
                {
                    _isHoldRecording = true;
                    _logger.LogInformation(">>> Hold started (Ctrl+Win)");
                    RecordingStarted?.Invoke();
                }
            }
            else if (isUp)
            {
                if (isCtrl) _ctrlHeld = false;
                if (isShift) _shiftHeld = false;
                if (isAlt) _altHeld = false;
                if (isWin) _winHeld = false;

                // Stop hold-recording when either Ctrl or Win released
                if (_isHoldRecording && (!_ctrlHeld || !_winHeld))
                {
                    _isHoldRecording = false;
                    _otherKeyPressed = false;
                    _logger.LogInformation(">>> Hold stopped (released)");
                    RecordingStopped?.Invoke();
                }

                if (!_ctrlHeld && !_winHeld)
                    _otherKeyPressed = false;
            }
        }

        return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    public bool ProcessHotkeyMessage(int hotkeyId) => false;

    public void Unregister()
    {
        if (!_registered) return;
        if (_hookHandle != IntPtr.Zero) { UnhookWindowsHookEx(_hookHandle); _hookHandle = IntPtr.Zero; }
        _registered = false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        Unregister();
        _disposed = true;
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
}
