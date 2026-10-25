# Metrics Design — MarsinDictation

> Track system health, API usage, and transcription quality via a local JSONL-based ledger.

---

## Storage

- **Directory:** `.metrics/` (repo root, gitignored)
- **Format:** [JSONL](https://jsonlines.org/) — one JSON object per line, append-only
- **File naming:** `YYYY-MM.jsonl` (monthly rotation)

```
.metrics/
  2026-03.jsonl
  2026-04.jsonl
```

---

## Event Schema

Each line is a JSON object with a common header:

```json
{
  "ts": "2026-03-13T17:01:00Z",
  "event": "transcription",
  "provider": "openai",
  "model": "gpt-4o-mini-transcribe",
  "audio_bytes": 487738,
  "audio_seconds": 1.3,
  "latency_ms": 873,
  "input_tokens": 12,
  "output_tokens": 6,
  "total_tokens": 18,
  "success": true,
  "text_length": 18,
  "error": null
}
```

### Event Types

| Event | Description | Key Fields |
|-------|-------------|------------|
| `transcription` | One transcription API call | `provider`, `model`, `audio_bytes`, `audio_seconds`, `latency_ms`, `input_tokens`, `output_tokens`, `total_tokens`, `success`, `text_length`, `error` |
| `recording` | One hold-to-record session | `duration_seconds`, `audio_bytes`, `cancelled` |
| `recovery` | Alt+Shift+Z recovery attempt | `had_pending`, `success` |
| `injection` | Text injection attempt | `method`, `char_count`, `success`, `target_app` |
| `startup` | App launch | `version`, `provider`, `model`, `os_version` |
| `error` | Unhandled error | `component`, `message`, `stack_trace` |

---

## Derived Metrics

Computed from the JSONL ledger (read-only aggregation):

### Health Dashboard

| Metric | Derivation |
|--------|------------|
| **Total transcriptions** | Count of `transcription` events |
| **Success rate** | `success=true` / total × 100 |
| **Avg latency** | Mean `latency_ms` for `transcription` events |
| **P95 latency** | 95th percentile `latency_ms` |
| **Total tokens** | Sum of `total_tokens` |
| **Total audio (min)** | Sum of `audio_seconds` / 60 |
| **Avg audio duration** | Mean `audio_seconds` |
| **Error rate by type** | Group `error` field, count |
| **Tokens by model** | Group by `model`, sum `total_tokens` |
| **Daily usage** | Group by date, count events |

### Cost Estimation

| Model | Input | Output |
|-------|-------|--------|
| `gpt-4o-mini-transcribe` | $0.005/min audio | included |
| `whisper-1` | $0.006/min audio | included |

Estimated cost = sum(`audio_seconds`) / 60 × rate_per_minute

---

## Implementation Notes

1. **Write path:** `MetricsLogger.cs` appends to `.metrics/YYYY-MM.jsonl` using `System.Text.Json`
2. **Read path:** Python script or dashboard reads JSONL for aggregation
3. **Concurrency:** File append is atomic on Windows for single-line writes
4. **Privacy:** No transcription text stored in metrics — only `text_length`
5. **Location:** `.metrics/` uses the repo root (same as `.env`), found via `EnvLoader`'s repo root detection

---

## Future Extensions

- CLI command: `python devtool/deploy.py --metrics` to print summary
- Export to CSV for spreadsheet analysis
- Daily/weekly digest notification
