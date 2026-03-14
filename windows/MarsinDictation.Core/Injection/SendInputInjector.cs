using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.Injection;

/// <summary>
/// Injects text into the focused application using Win32 SendInput
/// with KEYEVENTF_UNICODE — types each character as a Unicode keystroke.
/// Never touches the clipboard.
/// </summary>
public sealed class SendInputInjector
{
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_UNICODE = 0x0004;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private readonly ILogger<SendInputInjector> _logger;

    /// <summary>Delay between keystrokes in milliseconds (0 = no delay).</summary>
    public int InterKeystrokeDelayMs { get; set; } = 0;

    public SendInputInjector(ILogger<SendInputInjector> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Inject text into the currently focused window via SendInput.
    /// Returns the number of characters successfully injected.
    /// </summary>
    public int InjectText(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            _logger.LogWarning("InjectText called with empty text");
            return 0;
        }

        _logger.LogInformation("Injecting {Length} chars into focused window", text.Length);
        _logger.LogDebug("INPUT struct size: {Size} bytes", Marshal.SizeOf<INPUT>());

        int totalSent = 0;

        try
        {
            foreach (char c in text)
            {
                // Each character needs a key-down and key-up event
                var inputs = new INPUT[2];

                // Key down
                inputs[0].type = INPUT_KEYBOARD;
                inputs[0].u.ki.wVk = 0;
                inputs[0].u.ki.wScan = c;
                inputs[0].u.ki.dwFlags = KEYEVENTF_UNICODE;
                inputs[0].u.ki.time = 0;
                inputs[0].u.ki.dwExtraInfo = GetMessageExtraInfo();

                // Key up
                inputs[1].type = INPUT_KEYBOARD;
                inputs[1].u.ki.wVk = 0;
                inputs[1].u.ki.wScan = c;
                inputs[1].u.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
                inputs[1].u.ki.time = 0;
                inputs[1].u.ki.dwExtraInfo = GetMessageExtraInfo();

                uint sent = SendInput(2, inputs, Marshal.SizeOf<INPUT>());
                if (sent == 2)
                {
                    totalSent++;
                }
                else
                {
                    var err = Marshal.GetLastWin32Error();
                    _logger.LogWarning("SendInput failed at char {Index} ('{Char}'), Win32 error: {Error}",
                        totalSent, c, err);
                    break;
                }

                if (InterKeystrokeDelayMs > 0)
                    Thread.Sleep(InterKeystrokeDelayMs);
            }

            _logger.LogInformation("Injected {Sent}/{Total} chars", totalSent, text.Length);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Injection failed after {Sent} chars", totalSent);
        }

        return totalSent;
    }

    /// <summary>True if all characters were successfully injected.</summary>
    public bool TryInjectText(string text) => InjectText(text) == text.Length;

    /// <summary>Simulate Ctrl+V keystroke (for clipboard paste).</summary>
    public void SimulateCtrlV()
    {
        const ushort VK_CONTROL = 0x11;
        const ushort VK_V = 0x56;

        var inputs = new INPUT[4];

        // Ctrl down
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = VK_CONTROL;
        inputs[0].u.ki.dwFlags = 0;

        // V down
        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].u.ki.wVk = VK_V;
        inputs[1].u.ki.dwFlags = 0;

        // V up
        inputs[2].type = INPUT_KEYBOARD;
        inputs[2].u.ki.wVk = VK_V;
        inputs[2].u.ki.dwFlags = KEYEVENTF_KEYUP;

        // Ctrl up
        inputs[3].type = INPUT_KEYBOARD;
        inputs[3].u.ki.wVk = VK_CONTROL;
        inputs[3].u.ki.dwFlags = KEYEVENTF_KEYUP;

        uint sent = SendInput(4, inputs, Marshal.SizeOf<INPUT>());
        _logger.LogDebug("SimulateCtrlV: sent {Sent}/4 events", sent);
    }

    // ── Win32 P/Invoke ──────────────────────────────────────────
    // The INPUT struct must match Win32's native layout exactly.
    // On 64-bit: INPUT = 40 bytes (4 type + 4 pad + 32 union).
    // The union must be sized to MOUSEINPUT (the largest member).

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern IntPtr GetMessageExtraInfo();

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUTUNION u;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi;  // ensures correct union size
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
}
