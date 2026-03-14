# Agent-Driven Testing Framework — MarsinDictation

> Tests are not just for CI. They are the **primary evidence** that the system works correctly, in a form readable by both humans and agents.

This framework defines how tests should be written, what test output must communicate, and how the suite should be reviewed.

---

## Purpose

The testing system should make it easy for a reviewer to answer:

1. What state the system started in
2. What behavior was being tested
3. What evidence was expected
4. What was actually observed
5. Whether the result passed or failed, and why
6. What parts of the product are covered, mocked, manual-only, or out of scope

The goal is not just "green tests." The goal is **trustworthy evidence**.

---

## Core Principle: Evidence Over Silence

Test output is the primary evidence that the system works.

For important behavior tests, a person with **no access to the source code** — only the verbose test output — should be able to understand:

- the setup
- the intent
- the expected result
- the observed result
- the final verdict

> [!IMPORTANT]
> If the verbose output does not let a reviewer judge correctness without opening the code, the test is not sufficient. Rewrite it until the output tells the story clearly.

---

## Two Output Modes

The framework supports two output modes:

### Compact Output

Used for fast scanning during local development and CI summaries.

Compact output should show:
- test name
- setup
- intent
- pass/fail verdict

Example:

```text
DictationStateTests (16/16)
  ✔ ToggleDictation_FromIdle_GoesToRecording
      ┌ SETUP:  DictationService created fresh — state is Idle
      │ INTENT: When the user presses the dictation hotkey from idle, recording starts
      └ ✔ PASS: service entered Recording state from Idle
```

### Verbose Output

Used for real review, signoff, changed-test inspection, and debugging.

Verbose output should show:
- setup
- intent
- expected evidence
- observed values
- pass/fail verdict with reason

Example:

```text
DictationStateTests (16/16)
  ✔ ToggleDictation_FromIdle_GoesToRecording
      ┌ SETUP:  DictationService created fresh — state is Idle
      │ INTENT: When the user presses the dictation hotkey from idle, recording starts
      │ EXPECT: State changes from Idle → Recording
      │ GOT:    Initial state = Idle
      │ GOT:    State after toggle = Recording
      └ ✔ PASS: service entered Recording state from Idle
```

> [!IMPORTANT]
> Compact output is for scanning. Verbose output is the review artifact.

---

## Test Categories

Not every test needs the same amount of ceremony.

### 1. Evidence Tests

Use full evidence-style output for:

- state machines
- persistence and storage behavior
- settings/defaults compliance
- recovery logic
- privacy-sensitive logic
- any behavior tied directly to a design doc or user-facing guarantee

These tests must follow the full framework below.

### 2. Lightweight Tests

Use simpler tests for:

- small pure helpers
- parsing helpers
- deterministic formatting helpers
- tiny utility behavior with very obvious assertions

These tests do not need full narrative evidence output unless they protect important behavior.

> [!NOTE]
> The point is not to make every tiny test theatrical. The point is to make important tests readable and trustworthy.

### 3. Manual / Integration Verification

Some behaviors are not good candidates for ordinary automated tests, such as:

- global hotkey registration with the OS
- real microphone device behavior
- real external app injection
- permission dialogs
- tray/menu bar visual behavior
- hardware-dependent failure paths

These should be documented as:
- manual verification
- integration validation
- or explicitly out of scope for automated tests

---

## EvidenceTest Base Class

All evidence-style test classes derive from `EvidenceTest`, which provides structured output methods via `ITestOutputHelper`.

### Required Constructor

```csharp
public class MyTests : EvidenceTest
{
    public MyTests(ITestOutputHelper output) : base(output) { }
}
```

### Evidence Methods

| Method | Purpose | Output Format |
|--------|---------|---------------|
| `Setup(string)` | Describe the starting state / preconditions | `┌ SETUP:  ...` |
| `Intent(string)` | Describe what is being tested in plain English | `│ INTENT: ...` |
| `Expect(string)` | State what evidence is expected | `│ EXPECT: ...` |
| `Got(string, object?)` | Log an observed value | `│ GOT:    label = value` |
| `AssertEvidence<T>(string, T expected, T actual)` | Log + assert equality | `│ GOT:` on pass, `└ ✗ FAIL:` on mismatch |
| `AssertEvidence(string, bool)` | Log + assert boolean condition | Same as above |
| `Pass(string)` | Log the passing verdict with reason | `└ ✔ PASS: reason` |

### Required Call Order

Every evidence-style test must follow this sequence:

```
Setup(...)        ← always first, exactly once
Intent(...)       ← exactly once
Expect(...)       ← one or more
Got(...)          ← optional
AssertEvidence    ← one or more
Pass(...)         ← always last, specific reason required
```

> [!CAUTION]
> `Pass()` requires a real reason. Generic messages like `ok`, `done`, or `passed` are not allowed.

---

## Test Structure Rules

### 1. Setup Must Describe Starting State

Every evidence-style test begins with `Setup()` that explains what exists before the test runs.

```csharp
// ✔ Good
Setup("DictationService created fresh — state is Idle, no recording active");
Setup("TranscriptStore with 2 entries: one Success, one Pending");
Setup("Empty temp directory, no settings.json exists");

// ✗ Bad
Setup("initial state");
Setup("ready");
```

### 2. One Intent per Test

Each test verifies **one behavior**. The `Intent()` sentence should be understandable without reading code.

```csharp
// ✔ Good
Intent("When no settings file exists, loading creates one with design-doc defaults");

// ✗ Bad
Intent("Test settings");
```

### 3. Expect Before Assert

State the expected evidence before asserting it.

```csharp
Setup("Empty TranscriptStore, no entries");
Intent("New transcriptions appear at the top (newest first)");
Expect("After adding 'first' then 'second', list order is [second, first]");
```

This makes failures easier to diagnose and makes verbose output reviewable.

### 4. Evidence Labels Must Be Human-Readable

Labels should explain the value, not mirror variable names.

```csharp
// ✔ Good
AssertEvidence("State after toggle", DictationState.Recording, service.State);
AssertEvidence("Settings file created", true, File.Exists(path));

// ✗ Bad
AssertEvidence("x", expected, actual);
AssertEvidence("result", true, flag);
```

### 5. Pass Must Explain the Verdict

A passing verdict must say **what** was verified.

```csharp
// ✔ Good
Pass("all 9 defaults match the design document");
Pass("state transition applied successfully");
Pass("gracefully returned false");

// ✗ Bad
Pass("ok");
Pass("passed");
```

### 6. Tests Must Be Independent

Each test owns its own state and cleanup.

```csharp
public class MyTests : EvidenceTest, IDisposable
{
    private readonly string _testDir;

    public MyTests(ITestOutputHelper output) : base(output)
    {
        _testDir = Path.Combine(Path.GetTempPath(), "Test_" + Guid.NewGuid().ToString("N"));
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, recursive: true);
    }
}
```

---

## Failure Output Must Also Be Readable

A framework that only explains passing tests is half a framework.

Failure output must make it easy to see:
- what was expected
- what was observed
- why the assertion failed

Example:

```text
  ┌ SETUP:  New AppSettings() instance — pure constructor defaults
  │ INTENT: Constructor defaults match the design doc
  │ EXPECT: LaunchAtStartup defaults to false
  │ GOT:    LaunchAtStartup = true
  └ ✗ FAIL: LaunchAtStartup expected false but got true
```

> [!IMPORTANT]
> At least some tests should be validated by intentionally forcing a failure during framework development, to verify that the failure output is actually useful.

---

## Deploy Tool Integration

The deploy/test tooling exposes both compact and verbose evidence views.

```
python devtool/deploy.py --test             # Compact: SETUP + INTENT + PASS/FAIL
python devtool/deploy.py --test --verbose   # Full: all evidence lines
```

> [!IMPORTANT]
> Changed tests should be reviewed in verbose mode before signoff.

---

## Review Requirements

For meaningful review, the following artifacts are expected:

### 1. Compact Suite Output

Used as the quick dashboard.

### 2. Verbose Output for Changed Tests

Used as the actual evidence artifact for review.

### 3. Coverage Map Against the Design Doc

A lightweight mapping that shows which design requirements are covered by which tests.

| Requirement | Test Coverage | Type |
|-------------|--------------|------|
| Dictation toggles Idle → Recording | `DictationStateTests.ToggleDictation_FromIdle_GoesToRecording` | Unit |
| State transitions follow allowed paths | `DictationStateTests.IsValidTransition_ReturnsExpected` ×12 | Unit |
| StateChanged events fire for UI updates | `DictationStateTests.StateChanged_FiresOnTransition` | Unit |
| Reset recovers to Idle from any state | `DictationStateTests.Reset_AlwaysReturnsToIdle` | Unit |
| Settings defaults match design doc | `SettingsManagerTests.Defaults_MatchDesignDoc` | Unit |
| Settings survive app restart | `SettingsManagerTests.Persistence_RoundTrip` | Unit |
| No settings file → creates defaults | `SettingsManagerTests.Load_NoFile_CreatesDefaults` | Unit |
| Transcripts stored newest-first | `TranscriptStoreTests.Add_InsertsAtFront` | Unit |
| Transcript state filtering (recovery) | `TranscriptStoreTests.GetMostRecent_FiltersByState` | Unit |
| Transcript state transitions persist | `TranscriptStoreTests.UpdateState_ChangesStateAndPersists` | Unit |
| Transcript history survives restart | `TranscriptStoreTests.Persistence_RoundTrip` | Unit |
| Clear wipes transcript history | `TranscriptStoreTests.Clear_RemovesAll` | Unit |
| Graceful handling of unknown IDs | `TranscriptStoreTests.UpdateState_ReturnsFalseForUnknownId` | Unit |
| Clipboard restoration after injection | — | Manual |
| Ctrl+Shift hold-to-record hotkey | — | Manual |
| Alt+Shift+Z recovery hotkey | — | Manual |
| Tray icon quit functionality | — | Manual |
| Audio capture via WASAPI | — | Manual |

### 4. Mock / Real Boundary Notes

Every test area should make clear what is real, mocked, manual-only, or out of scope.

| Area | Strategy |
|------|----------|
| State machine | Pure unit |
| Settings persistence | Real temp filesystem |
| Transcript store | Real temp filesystem |
| OpenAI client | Mocked HTTP (not yet implemented) |
| Global hotkey registration | Manual verification |
| External app text injection | Manual verification |
| Audio capture / playback | Manual verification |
| Tray icon / status window | Manual verification |

---

## When to Write Tests

| Scenario | Required? |
|----------|-----------|
| New core logic (state machines, data models) | ✅ Yes |
| Settings / persistence round-trips | ✅ Yes |
| Design doc compliance (defaults match spec) | ✅ Yes |
| Privacy-sensitive local storage behavior | ✅ Yes |
| Recovery behavior | ✅ Yes |
| UI layout / visual appearance | ❌ No (manual verification) |
| Platform-specific interop (hotkeys, audio) | ❌ No (manual / integration validation) |
| Integration with external APIs (OpenAI / LocalAI) | ⚠ Mock only in ordinary tests |

---

## File Locations

```
windows/
  MarsinDictation.Tests/
    EvidenceTest.cs              ← base class
    DictationStateTests.cs       ← state machine transitions
    SettingsManagerTests.cs      ← settings persistence and defaults
    TranscriptStoreTests.cs      ← transcript CRUD and persistence
```

## Adding New Test Files

1. Create a new `.cs` file in `MarsinDictation.Tests/`
2. Add a **module-level XML doc comment** explaining what the file tests and why
3. Derive from `EvidenceTest` if the file contains evidence-style tests
4. Accept `ITestOutputHelper` in the constructor
5. Follow the `Setup → Intent → Expect → AssertEvidence → Pass` pattern for evidence tests
6. Run verbose mode and verify the output tells the story without looking at code
7. Update the design-doc coverage map if the tests protect a documented requirement

### Module-Level Intent (Required)

Every evidence-style test class must have a `<summary>` XML doc comment explaining:
- **What component** is being tested
- **Why** these tests exist (what they protect against)
- **What the tests cover** at a high level

```csharp
/// <summary>
/// Tests for the TranscriptStore — the local history of all dictation transcriptions.
///
/// These tests verify that:
///   - Entries are stored newest-first
///   - Entries can be filtered by state
///   - State transitions persist to disk
///   - The store survives app restarts
///   - Clear wipes all data for privacy
///
/// Without these tests, a broken store could silently lose transcript history
/// or break the recovery hotkey's ability to find recent transcriptions.
/// </summary>
public class TranscriptStoreTests : EvidenceTest, IDisposable
{
    ...
}
```

---

## Out-of-Scope or Manual-Only Areas

The test strategy must explicitly name areas that are **not** covered by normal automated tests.

Typical examples:
- OS-level hotkey registration
- real microphone hardware behavior
- actual text insertion into third-party apps
- permission prompts and system dialogs
- tray/menu bar visual behavior
- external API availability or latency

These should not remain ambiguous. If not covered by automated tests, they must be marked as:
- manual verification
- integration validation
- or intentionally out of scope

---

## Test Data & Fixtures

Some tests require real data files (e.g., audio WAV files for transcription tests). These live in `windows/MarsinDictation.Tests/TestData/`.

To generate test data, use utilities from `util/`:

- **`util/record.py`** — record audio from the microphone into a WAV file
  - See [`01_designs/03_utils.md`](../01_designs/03_utils.md) for usage

Tests that depend on external data files must gracefully skip if the file is missing (not fail), and clearly state what command to run to generate the data.

---

## Agent Test Debugging Workflow

> If tests pass, you have a good day! If they didn't pass, you still have a good day, but — find the failing test(s), compile a list of names, then add `--filter` and `--verbose` to the `--test` command in `deploy.py` and run the tests again. Then check the verbose outputs from those failing tests and fix them. Then it will be a beautiful day with no bug! :)

Steps:

1. Run `python devtool/deploy.py --test`
2. If all pass → ✔ done
3. If any fail → note the failing test names
4. Run `python devtool/deploy.py --test --filter "FailingTestName" --verbose`
5. Read the verbose evidence output (SETUP, INTENT, EXPECT, GOT)
6. Fix the code
7. Repeat from step 4 until all filtered tests pass
8. Run the full suite again (`--test` without `--filter`) to confirm nothing else broke

---

## Final Rule

Tests are not decoration. They are evidence.

A good test suite should help a human or an agent decide, with minimal guesswork:

- what works
- what failed
- what changed
- what is still unverified
