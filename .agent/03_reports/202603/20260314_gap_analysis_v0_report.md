# Report: Gap Analysis — 2026-03-14

## Summary

This report maps the current codebase against the Windows v0 design (`01_win_design_v0.md`) and project plan (`20260313_1_win_app_v0.md`). The analysis is based on **direct source code audit**, not the project plan's checkboxes.

## Work Completed (Verified in Source)

### Phase 0: Bootstrap & Walking Skeleton ✅
- WPF app structure, tray icon (`H.NotifyIcon.Wpf`) with custom multi-resolution `.ico`
- `WH_KEYBOARD_LL` low-level keyboard hook for Ctrl+Win hold-to-record
- `RegisterHotKey` for Alt+Shift+Z recovery
- `SettingsManager`, `SecretStore` (DPAPI), `EnvLoader` (.env parsing)
- `TranscriptStore` — upgraded to sharded JSONL (monthly files)
- Full evidence-based test suite (39+ tests)
- `deploy.py` — `--build`, `--run`, `--test`, `--hold`, `--install` modes
- `build_icon.ps1` — automated multi-resolution `.ico` generation from `icon.png`

### Phase 1: Core App Infrastructure ✅
- Real-time orchestration wired in `App.xaml.cs` (record → transcribe → inject → store)
- `StatusWindow` overlay — passive ghost window (`WS_EX_NOACTIVATE`, `WS_EX_TRANSPARENT`)
- Recovery hotkey (`Alt+Shift+Z`) wired and functional — re-injects `_lastTranscription`
- Tray menu: Settings, History (stub), Open User Data, Clean User Data, Quit

### Phase 2: Audio Capture ✅
- `AudioRecorder.cs` — WASAPI microphone capture via NAudio
- WAV encoding to `MemoryStream` (NAudio `WaveFileWriter`)
- `AudioPlayer.cs` — playback for fallback when no API key is set

### Phase 3: Transcription ✅
- `ITranscriptionClient` abstraction
- `OpenAITranscriptionClient` — supports both OpenAI and LocalAI (same class, configurable base URL and auth)
- Provider selection via `.env` (`MARSIN_TRANSCRIPTION_PROVIDER=openai|localai`)
- Model selection via `.env` (`OPENAI_MODEL`, `LOCALAI_MODEL`)
- Live transcription confirmed working end-to-end

### Phase 4: Injection ✅
- `SendInputInjector.cs` — full `KEYEVENTF_UNICODE` implementation with per-character key-down/key-up
- `TryInjectText()` returns success/failure, wired to `TranscriptState.Success` / `Pending`
- Clipboard fallback: if `SendInput` fails, text is copied to clipboard + toast notification
- `SimulateCtrlV()` helper exists for clipboard-paste fallback path
- Transcripts saved to `TranscriptStore` with state tracking on every injection attempt

---

## Remaining Gaps

### Architecture: `DictationService.cs` Is a Skeleton
- `DictationService.cs` still contains Phase 0 placeholder code (comments like "Phase 1+: start WASAPI capture here")
- **All real orchestration lives directly in `App.xaml.cs`** (`OnHoldRecordStart`, `OnHoldRecordStop`, `DoInjectText`, `OnRecoveryPressed`)
- The state machine in `DictationService` is well-defined but **not used at runtime** — `App.xaml.cs` manages state implicitly
- **Recommendation:** Either refactor `App.xaml.cs` orchestration into `DictationService`, or document the current architecture as intentional

### Missing: AudioGuard (25 MB Upload Limit)
- No `AudioGuard.cs` exists anywhere in the codebase
- The design specifies auto-stopping recording before exceeding 25 MB
- Risk: very long recordings will exceed OpenAI's upload limit and fail

### Missing: TextPostProcessor (Filler Word Removal)
- No `TextPostProcessor.cs` exists
- Design specifies stripping "um", "uh", "like" and fixing punctuation/capitalization
- Current behavior: raw transcription text is injected as-is (OpenAI models may already clean this)

### Missing: Per-App Exclusion List
- No exclusion logic exists in the codebase
- Design specifies checking the foreground app against an exclusion list before recording

### Missing: Settings UI
- `MainWindow.xaml` is a static placeholder ("Settings will be implemented in Phase 5")
- No UI for configuring hotkeys, provider, API key, model selection, or language
- All configuration is currently `.env`-only

### Missing: History Panel
- Tray menu has a "History" item but its click handler is a no-op (`/* Phase 5: open history panel */`)
- Transcript data is stored (JSONL) but has no UI to browse it

### Design Deviation: Clipboard Usage
- Design doc states: **"The app never touches the system clipboard"**
- Actual code (`App.xaml.cs:221`): `Clipboard.SetText(text)` is called on **every** injection, even when `SendInput` succeeds
- This is a deviation from the design — may be intentional as a convenience feature, but should be documented

---

## Summary Table

| Component | Design Status | Code Status |
|-----------|:---:|:---:|
| WPF Tray App Shell | ✅ | ✅ |
| Hold-to-Record Hotkey | ✅ | ✅ |
| Recovery Hotkey (Alt+Shift+Z) | ✅ | ✅ |
| WASAPI Audio Capture | ✅ | ✅ |
| OpenAI Transcription | ✅ | ✅ |
| LocalAI Transcription | ✅ | ✅ (same client, configurable) |
| SendInput Text Injection | ✅ | ✅ |
| Injection Failure → Pending | ✅ | ✅ |
| TranscriptStore (JSONL) | ✅ | ✅ |
| StatusWindow Overlay | ✅ | ✅ (passive, non-focus-stealing) |
| Multi-res Icon & Install | ✅ | ✅ |
| DictationService Orchestrator | ✅ | 🚧 Skeleton only |
| AudioGuard (25 MB limit) | ✅ | ❌ Not implemented |
| TextPostProcessor | ✅ | ❌ Not implemented |
| Per-App Exclusion List | ✅ | ❌ Not implemented |
| Settings UI Window | ✅ | ❌ Placeholder |
| History Panel | ✅ | ❌ Stub |
| Clipboard isolation | ✅ | ⚠ Clipboard used as backup |

## Recommendations

1. **Highest priority:** AudioGuard — without it, long recordings will fail at the API level
2. **Next:** Decide whether to refactor orchestration into `DictationService` or document the `App.xaml.cs` approach as canonical
3. **Then:** Settings UI — currently all config requires `.env` editing, which is not user-friendly
4. **Low priority:** TextPostProcessor (OpenAI models already clean output), per-app exclusion list, History panel
