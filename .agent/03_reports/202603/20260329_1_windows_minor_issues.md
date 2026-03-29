# MarsinDictation - Windows Minor Issues Report

Based on an investigation of the current `MarsinDictation` Windows project, here is a full report on why the identified bugs are happening and what must change to fix them.

## 1. Recording UI Not Showing on Main Screen When HDMI is Removed
**What is broken**: When you unplug your secondary HDMI monitor, the `StatusWindow` (the toast popup) fails to appear.
**Why it happens**: WPF uses `SystemParameters.WorkArea` to position the toast in `StatusWindow.xaml.cs > PositionWindow()`. When a monitor is hot-unplugged, the window might retain coordinates that exist in an off-screen region, or WPF's `SystemParameters` cache might not immediately update the boundaries of the primary monitor. If the window's `Left` and `Top` properties are recalculated using stale multi-monitor geometry, it gets rendered outside the visible area of your active laptop screen.
**What needs to change**:
We need to change `PositionWindow()` to strictly query the live bounds of the primary monitor using `System.Windows.Forms.Screen.PrimaryScreen.WorkingArea` (which evaluates to the active primary display on the fly and is more robust against hot-plugging than WPF's static `SystemParameters`). We'll ensure the toast clamps properly to the active primary bounds whenever `ShowToast` is called.

## 2. Clipboard Being Overwritten by Transcription
**What is broken**: The system clipboard is overwritten with the transcribed text every time you dictate.
**Why it happens**: Inside `App.xaml.cs > DoInjectText()`, there is an unconditional call to `System.Windows.Clipboard.SetText(text);` immediately before it uses `SendInputInjector` to type out the transcription.
**What needs to change**:
We will remove `System.Windows.Clipboard.SetText(text);`.
Because the application uses `SendInput` (simulating keystrokes natively), it doesn't need the clipboard to insert text into the active window. `Alt+Shift+Z` is already wired up to call `DoInjectText(_lastTranscription)`. By removing the clipboard overwrite, your clipboard will remain completely untouched. If the primary typing injection fails natively for some reason, we can define a fallback where it conditionally copies it to the clipboard as a last resort, or we can just never touch the clipboard and let `Alt+Shift+Z` retry the typing.

## 3. Local AI Transcriptions Failing on Long Dictations
**What is broken**: Long audio transcriptions sent to LocalAI fail outright.
**Why it happens**: The `OpenAITranscriptionClient.cs` orchestrates the HTTP requests to LocalAI utilizing a standard .NET `HttpClient`. By default, `.NET` sets `HttpClient.Timeout` to strictly 100 seconds. When you send a large transcription to LocalAI (running locally, likely on CPU or lacking raw GPU speed), it naturally takes longer than 100 seconds to transcribe. The app forcefully aborts the request at the 100-second mark, causing a `TaskCanceledException` and the transcription essentially fails.
**What needs to change**:
We need to initialize the `HttpClient` in `OpenAITranscriptionClient.cs` with `Timeout = TimeSpan.FromMinutes(5)` (or `Timeout.InfiniteTimeSpan`). This allows the LocalAI instance as much time as it needs to process the speech without the app artificially canceling the operation.

## 4. "Transcribing..." Toast Gets Stuck Indefinitely
**What is broken**: After recording stops, the "⏳ Transcribing..." toast sometimes stays on screen forever and is never replaced by the success/failure toast.
**Why it happens**: In `App.xaml.cs > OnHoldRecordStop()`, the entire post-recording flow runs inside a `Dispatcher.Invoke(async () => ...)` lambda. This is effectively an `async void` delegate — any unhandled exception is silently swallowed. If `DoInjectText()` throws (e.g. `Clipboard.SetText` fails because the clipboard is locked by another app, or `_injector.TryInjectText` throws), the code never reaches the line that shows the success/failure toast. The "Transcribing..." toast was set with a 30-second timer (`ToastType.Playing, 30.0`), so it lingers for up to 30 seconds looking completely stuck.
**What needs to change**:
Wrap the entire post-transcription flow in `OnHoldRecordStop()` in a `try/catch/finally` block. The `finally` block should guarantee the toast is always updated (either with the result or an error message), so the UI never gets stuck regardless of what goes wrong internally.
