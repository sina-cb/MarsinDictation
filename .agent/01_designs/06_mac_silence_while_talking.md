# MarsinDictation — macOS: Silence System Audio While Hotkey Held

> **Status:** Approved — Implemented
> **Author:** Engineering
> **Date:** 2026-03-19
> **Depends on:** [02_mac_design_v0.md](./02_mac_design_v0.md)

---

## 1. Problem Statement

When a user holds the dictation hotkey (Control+Option) to record speech, any system audio that is currently playing — music, video conferencing, notification sounds, YouTube, etc. — bleeds into the microphone input. This is especially severe with laptop speakers, but also affects external speakers and some headset configurations. The result:

- **Degraded transcription quality.** Whisper and similar models hallucinate or produce garbage when background audio is prominent.
- **Leaked content in transcripts.** Song lyrics, podcast dialogue, or meeting audio can appear in the transcription output.
- **Broken user expectation.** Users instinctively expect a dictation tool to "just work" regardless of what media they have playing.

### Problem Scope

This design addresses **system audio output silencing only**. It does not cover:

- Mic input noise suppression (e.g., using RNNoise or similar) — separate feature
- Active noise cancellation at the hardware level
- Silencing specific applications while leaving others audible

---

## 2. Goal

When the user presses and holds the dictation hotkey:

1. **Immediately duck all system audio output to 10%** so that speakers/headphones become near-silent.
2. **Recording proceeds as normal** with minimal audio interference from system playback.
3. **When the hotkey is released**, system audio is restored to its previous volume — seamlessly, as if nothing happened.

The user should feel like pressing the hotkey puts the system into "dictation mode" where everything goes quiet and their voice is the only input.

---

## 3. Approach Analysis

There are several technical paths to silencing system audio on macOS. Each has different trade-offs around permissions, reliability, and user experience.

### 3A. CoreAudio — Set System Output Volume to 0

**Mechanism:** Use `AudioObjectSetPropertyData` on the default output device (`kAudioHardwarePropertyDefaultOutputDevice`) to set its volume (`kAudioDevicePropertyVolumeScalar`) to 0 on all channels, then restore the original value on release.

| Aspect | Detail |
|--------|--------|
| **API** | CoreAudio C API (`AudioObjectSetPropertyData`) |
| **Permissions** | None — no entitlements, no Accessibility, no SIP bypass |
| **Reliability** | High — it is the same mechanism macOS volume keys use |
| **Latency** | Near-zero — volume change is synchronous |
| **Reversibility** | Save per-channel volume before muting, restore on release |
| **Edge cases** | Must handle multi-channel devices (stereo = L+R), headphone vs. speaker switching mid-recording, devices with no software volume control (some USB/Thunderbolt DACs) |
| **User perception** | Volume slider in menu bar drops to 0, media keeps "playing" silently. No glitches, no pauses. |

> [!TIP]
> CoreAudio volume control is how macOS's own volume keys work. This is the most native, lowest-friction, zero-permission approach.

### 3B. CoreAudio — Mute the Output Device

**Mechanism:** Use `kAudioDevicePropertyMute` instead of setting volume to 0. This is the programmatic equivalent of the hardware mute button on some keyboards.

| Aspect | Detail |
|--------|--------|
| **API** | CoreAudio C API (`AudioObjectSetPropertyData` with `kAudioDevicePropertyMute`) |
| **Permissions** | None |
| **Reliability** | High, but some devices don't support the mute property |
| **Difference from 3A** | Mute is a binary toggle, cleaner to save/restore. But not all audio devices expose a software mute property. |

### 3C. NSSound / AVAudioSession — Application-Level Control

Not applicable on macOS desktop. `AVAudioSession` is an iOS/tvOS API. `NSSound` controls per-sound playback, not system output. **Rejected.**

### 3D. AppleScript — `set volume output muted true`

**Mechanism:** Execute `osascript -e "set volume output muted true"` via `NSTask` / `Process`.

| Aspect | Detail |
|--------|--------|
| **Permissions** | None (AppleScript volume control works without Accessibility) |
| **Reliability** | Medium — subprocess spawn adds latency (~50–150ms), risk of race conditions |
| **Latency** | Noticeable — process spawning is not instantaneous |
| **Reversibility** | `set volume output muted false` + `set volume output volume <N>` |

> [!WARNING]
> AppleScript is a blunt instrument with variable latency. Not recommended when a direct C API call achieves the same result in microseconds.

### 3E. Virtual Audio Device (e.g., BlackHole, Soundflower)

**Mechanism:** Route system audio through a virtual device that can be programmatically controlled.

| Aspect | Detail |
|--------|--------|
| **Permissions** | Requires user to install a kernel extension or system extension |
| **Reliability** | Complex, fragile, version-dependent |
| **UX** | Terrible — forces users to install third-party audio drivers |

**Rejected for v0.** This is over-engineered for simple muting.

---

## 4. Recommended Approach: Hybrid Volume + Mute

**Primary:** Use CoreAudio `kAudioDevicePropertyMute` to mute the default output device.
**Fallback:** If the device doesn't support mute, set `kAudioDevicePropertyVolumeScalar` to 10% (0.1) on all channels.

> [!NOTE]
> **Decision (2026-03-19):** User approved 10% ducking over full mute for a more pleasant UX. The `duckLevel` constant in `AudioSilencer.swift` is set to `0.1`.

This gives us:

- **Zero additional permissions** — no Accessibility, no entitlements
- **Near-zero latency** — CoreAudio property changes are synchronous kernel calls
- **Clean state management** — save mute state + volume before hotkey press, restore on release
- **No subprocess overhead** — direct C API, no AppleScript

### Why Mute-First

- Mute is a single boolean — no need to track per-channel volumes
- Restoring from mute is atomic — just unmute, volume stays at the user's original level
- For devices that don't support mute (rare), we fall back to volume zeroing with per-channel save/restore

---

## 5. Detailed Design

### 5.1 New Module: `AudioSilencer`

**Location:** `mac/Core/Audio/AudioSilencer.swift`

A stateless utility that mutes/unmutes the system's default output audio device.

```
┌─────────────────────────────────────────────────┐
│ AudioSilencer                                    │
├─────────────────────────────────────────────────┤
│ - savedMuteState: UInt32?                        │
│ - savedVolumes: [(channel: UInt32, vol: Float)]? │
│ - savedDeviceID: AudioDeviceID?                  │
│ - isCurrentlySilenced: Bool                      │
├─────────────────────────────────────────────────┤
│ + silence()    → Bool                            │
│ + restore()    → Bool                            │
│ + isEnabled: Bool  (SettingsManager)             │
├─────────────────────────────────────────────────┤
│ - getDefaultOutputDevice() → AudioDeviceID?      │
│ - getMuteState(device) → UInt32?                 │
│ - setMuteState(device, muted: Bool) → Bool       │
│ - getVolume(device, channel) → Float?            │
│ - setVolume(device, channel, vol) → Bool         │
│ - getChannelCount(device) → UInt32               │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**

1. **Snapshot on silence, restore on release.** `silence()` captures the current mute/volume state, then mutes. `restore()` puts it back exactly as it was.

2. **Device identity check.** If the output device changes between `silence()` and `restore()` (user plugs in headphones mid-recording), skip restoration — the new device is already at its own volume.

3. **Guard against double-silence.** If `silence()` is called while already silenced (shouldn't happen, but defensive coding), it's a no-op.

4. **Guard against orphaned silence.** If the app crashes or is force-quit while audio is silenced, the user is left with a muted system. Mitigations:
   - `deinit` calls `restore()`
   - `applicationWillTerminate` calls `restore()`
   - The user can always press their physical volume keys to override

### 5.2 CoreAudio Implementation Details

```swift
import CoreAudio

// Get default output device
var deviceID = AudioDeviceID(0)
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &address, 0, nil, &size, &deviceID
)

// Mute
var muted: UInt32 = 1
var muteAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyMute,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectSetPropertyData(
    deviceID, &muteAddress, 0, nil,
    UInt32(MemoryLayout<UInt32>.size), &muted
)

// Volume fallback (per-channel)
var volume: Float32 = 0.0
var volAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyVolumeScalar,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: 1  // channel 1 (left), 2 (right), etc.
)
AudioObjectSetPropertyData(
    deviceID, &volAddress, 0, nil,
    UInt32(MemoryLayout<Float32>.size), &volume
)
```

> [!NOTE]
> `kAudioObjectPropertyElementMain` (element 0) is the master channel. Channels 1, 2, ... are individual outputs. Some devices only expose the master channel; others only expose per-channel controls. The implementation must probe both.

### 5.3 Integration with DictationService

The `AudioSilencer` integrates into the existing hold-to-record flow at two points:

```
  User presses Control+Option
           │
           ▼
  HotkeyManager.dictationHotkeyPressed()
           │
           ▼
  DictationService.dictationHotkeyPressed()
           │
  ┌────────┴────────┐
  │  NEW: AudioSilencer.silence()  ◄── Mute system audio BEFORE capture
  └────────┬────────┘
           │
           ▼
  AudioCapture.startCapture()
  RecordingHUD shows "🔴 Recording..."
           │
     User speaks...
           │
  User releases Control+Option
           │
           ▼
  DictationService.dictationHotkeyReleased()
           │
           ▼
  AudioCapture.stopCapture()
           │
  ┌────────┴────────┐
  │  NEW: AudioSilencer.restore()  ◄── Unmute system audio AFTER capture stops
  └────────┬────────┘
           │
           ▼
  Transcription + Injection (unchanged)
```

**Ordering matters:**

- `silence()` is called **before** `AudioCapture.startCapture()` so that by the time the mic is recording, speakers are already silent.
- `restore()` is called **after** `AudioCapture.stopCapture()` so the WAV data is fully captured before audio resumes.

### 5.4 Integration Points in DictationService.swift

Changes to `DictationService.swift`:

```diff
 public class DictationService: HotkeyDelegate, AudioCaptureDelegate {
+    private let audioSilencer = AudioSilencer()
 
     public func dictationHotkeyPressed() {
         // ... exclusion check ...
         if !isRecording {
+            if SettingsManager.shared.silenceAudioDuringDictation {
+                audioSilencer.silence()
+            }
             RecordingHUDController.shared.showToast(text: "🔴 Recording...", type: .recording)
             startRecording()
         }
     }
 
     public func dictationHotkeyReleased() {
         if isRecording {
             stopRecording()
+            audioSilencer.restore()
         }
     }
```

> [!IMPORTANT]
> `restore()` is safe to call even if `silence()` was never called (i.e., the setting is off). It checks `isCurrentlySilenced` internally and no-ops.

### 5.5 Failure Safety

| Scenario | Behavior |
|----------|----------|
| `silence()` fails (device doesn't support mute OR volume) | Recording proceeds normally — degraded transcription, but no crash. Log warning. |
| App crashes while silenced | System stays muted. User recovers with physical volume keys / menu bar slider. This is the same behavior as if any app crashed while manipulating volume. |
| App terminates normally while silenced (force quit from menu bar) | `applicationWillTerminate` calls `audioSilencer.restore()`. Covered. |
| Output device changes mid-recording (headphones plugged in) | `restore()` detects device ID mismatch, skips restoration. New device is at its own volume — correct behavior. |
| User manually unmutes during recording | Fine — `restore()` will attempt to restore saved state, but since user already changed it, the volume may differ. Acceptable edge case. |
| `silence()` called while already silenced | No-op. Idempotent. |
| `restore()` called without prior `silence()` | No-op. Safe. |

### 5.6 Settings

Add one new user-facing setting:

| Setting | Key | Default | Type |
|---------|-----|---------|------|
| Silence audio during dictation | `silenceAudioDuringDictation` | `true` | Boolean |

**Why default to ON:**

- The whole point of this feature is to improve transcription quality transparently
- Users who do NOT want this (e.g., musicians monitoring playback) can toggle it off
- Defaulting to ON means the "it just works" experience for the majority

Changes to `SettingsManager.swift`:

```diff
+ @Published public var silenceAudioDuringDictation: Bool {
+     didSet { UserDefaults.standard.set(silenceAudioDuringDictation, forKey: Keys.silenceAudio) }
+ }

  private enum Keys {
+     static let silenceAudio = "silenceAudioDuringDictation"
  }
```

Changes to `SettingsView.swift`:

```diff
+ Toggle("Silence audio during dictation", isOn: $settings.silenceAudioDuringDictation)
+     .help("Mutes system audio while holding the dictation hotkey to prevent interference with transcription")
```

### 5.7 HUD Feedback

No new HUD states. The existing "🔴 Recording..." HUD is sufficient. The silence/restore happens transparently — the user's clue is that their music stops and resumes. Adding a "🔇 Muted" indicator would be noisy and redundant.

However, if `silence()` fails, we log a warning but do **not** show a HUD error — this is not a blocking failure.

---

## 6. AudioGuard Interaction

The `AudioGuard` module can auto-stop recording if the 25 MB limit is reached. When this happens, `AudioCapture` calls `audioLimitReached()` → `stopCapture()`. The `DictationService` must also call `audioSilencer.restore()` in this path.

Looking at the current code, `audioLimitReached()` is a delegate method on `AudioCapture` that calls `stopCapture()`. The `stopCapture()` method then triggers `readyToProcessWav()` on the delegate (DictationService). So `restore()` should also be called when processing the WAV:

```diff
  public func readyToProcessWav(wavData: Data) {
+     // Restore system audio now that capture is complete
+     audioSilencer.restore()
      // ... existing transcription logic ...
  }
```

This consolidation point (`readyToProcessWav`) handles both normal release and AudioGuard auto-stop, since both paths end up here. We can therefore simplify by calling `restore()` in `readyToProcessWav` instead of in `dictationHotkeyReleased()`.

> [!IMPORTANT]
> **Single restore point.** Rather than scattering `restore()` calls in multiple code paths (hotkey release, AudioGuard limit, crash handler), the primary restore should live in `readyToProcessWav()` + a safety net in `applicationWillTerminate`. The `readyToProcessWav()` callback is the canonical "recording is done" signal in the existing architecture.

---

## 7. Testing Strategy

### 7.1 Unit Test: AudioSilencer State Machine

Since CoreAudio is a system API, mock the low-level calls and test the state machine logic:

- `silence()` when not silenced → saves state, returns true
- `silence()` when already silenced → no-op, returns true
- `restore()` after `silence()` → restores state, returns true
- `restore()` without prior `silence()` → no-op, returns true
- `restore()` with different device ID → skips restoration, returns false
- `silence()` + crash simulation → `deinit` calls `restore()`

### 7.2 Integration Test: Manual Verification

1. Launch MarsinDictation, play music (e.g., Music.app, Spotify, YouTube)
2. Hold Control+Option — music should immediately go silent
3. Speak into microphone
4. Release Control+Option — music should resume at previous volume
5. Verify transcript does not contain music/speech artifacts

### 7.3 Edge Case Testing

| Test | Steps | Expected |
|------|-------|----------|
| Headphone hot-swap | Start recording with speakers → plug in headphones mid-recording → release | New device at its own volume, no crash |
| Very short hold | Tap Control+Option quickly (<200ms) | Audio mutes and unmutes almost instantly, no stuck state |
| AudioGuard auto-stop | Record a very long dictation (~5+ min) until AudioGuard triggers | Audio restores after auto-stop |
| Setting OFF | Disable "Silence audio during dictation" → hold hotkey | Audio keeps playing during recording |
| Multiple rapid holds | Hold → release → hold → release rapidly | No volume drift, clean state each time |
| App force quit while silenced | Hold hotkey, then `kill -9` the app | System audio stays muted; user restores with volume keys. `applicationWillTerminate` is NOT called on `kill -9` (this is an accepted limitation) |

---

## 8. Future Considerations (Not in Scope)

These are explicitly **not** part of this feature but may build on it later:

| Idea | Notes |
|------|-------|
| **Per-app audio control** | Mute only specific apps (e.g., Music but not a Zoom call). Requires user-space audio middleware — very complex. |
| **Visual audio meter** | Show real-time mic input level on the HUD so user can see their voice is being captured clearly. |
| **Automatic noise detection** | Skip silencing if the system audio output is below a threshold (nothing playing). Avoids unnecessary mute/unmute cycles. |

---

## 9. Module Structure (Post-Implementation)

```
mac/Core/Audio/
├── AudioCapture.swift        # Existing — mic capture
├── AudioGuard.swift          # Existing — 25 MB limit
└── AudioSilencer.swift       # NEW — system audio mute/restore
```

No new dependencies. No new entitlements. No new permissions.

---

## 10. Acceptance Criteria

- [ ] Holding the dictation hotkey ducks system audio output to 10%
- [ ] Releasing the hotkey restores system audio to its previous state (volume + mute)
- [ ] Feature works with built-in speakers, external speakers, and headphones
- [ ] Feature is controlled by a toggle in Settings (default: ON)
- [ ] App crash or force-quit does not permanently mute the system (user can recover via hardware volume)
- [ ] `applicationWillTerminate` restores audio as a safety net
- [ ] AudioGuard auto-stop correctly restores audio
- [ ] No new permissions or entitlements required
- [ ] Transcription quality measurably improves when music is playing vs. without this feature
