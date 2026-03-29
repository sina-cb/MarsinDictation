# LocalAI — Speech-to-Text Setup

> Design document for the local transcription backend used by MarsinDictation.

---

## Overview

MarsinDictation uses **LocalAI** as its default (and recommended) transcription provider. LocalAI is a self-hosted, open-source API server that exposes an **OpenAI-compatible** `/v1/audio/transcriptions` endpoint, enabling local, offline, and free speech-to-text transcription.

---

## Why LocalAI

| Advantage | Detail |
|-----------|--------|
| **Free** | No API costs — runs entirely on your machine |
| **Offline** | Works without internet after initial model download |
| **Private** | Audio never leaves your machine |
| **OpenAI-compatible** | Same `/v1/audio/transcriptions` endpoint — no code changes to switch providers |
| **Multiple backends** | Supports `whisper.cpp`, `faster-whisper`, `moonshine`, and more |

---

## Current Configuration

| Setting | Value |
|---------|-------|
| **Endpoint** | `http://localhost:3850` |
| **Model** | `whisper-1` |
| **Backend** | `whisper` on CUDA 12 GPU (via LocalAI) |
| **Audio format** | WAV, 48kHz, mono, 16-bit PCM |
| **API shape** | `POST /v1/audio/transcriptions` (multipart/form-data) |
| **Language** | `en` (configurable) |

---

## Installation

### 1. Install LocalAI

```bash
# macOS (Homebrew)
brew install localai

# Or via Docker
docker run -p 3850:8080 localai/localai:latest
```

### 2. Start with Whisper Model

```bash
# Start LocalAI on port 3850 with whisper-1
local-ai run whisper-1 --address :3850
```

Or use the Docker approach:
```bash
docker run -p 3850:8080 \
  -e MODELS=whisper-1 \
  localai/localai:latest
```

### 3. Verify

```bash
curl http://localhost:3850/v1/models
# Should list whisper-large-turbo
```

---

## Model Details

### whisper-large-turbo

| Property | Value |
|----------|-------|
| **Base model** | OpenAI Whisper Large v3 Turbo |
| **Parameters** | ~809M |
| **Backend** | whisper.cpp (quantized) |
| **Speed** | ~10x realtime on Apple Silicon |
| **Languages** | 99 languages (auto-detect or specify) |
| **Accuracy** | Near-parity with cloud Whisper API |
| **VRAM** | ~1.5 GB (quantized) or ~3 GB (f16) |

### Alternative Models

| Model | Size | Speed | Accuracy | Use case |
|-------|------|-------|----------|----------|
| `whisper-tiny` | 39M | Very fast | Lower | Quick testing, weak hardware |
| `whisper-base` | 74M | Fast | OK | Casual use |
| `whisper-small` | 244M | Medium | Good | Balanced |
| `whisper-medium` | 769M | Slower | Very good | When quality matters |
| `whisper-1` | 809M | Fast (optimized) | **Excellent** | **Recommended** |

---

## API Request Shape

MarsinDictation sends this request for transcription:

```http
POST /v1/audio/transcriptions HTTP/1.1
Host: localhost:3850
Content-Type: multipart/form-data; boundary=Boundary-UUID

--Boundary-UUID
Content-Disposition: form-data; name="model"

whisper-1
--Boundary-UUID
Content-Disposition: form-data; name="language"

en
--Boundary-UUID
Content-Disposition: form-data; name="file"; filename="audio.wav"
Content-Type: audio/wav

<WAV binary data>
--Boundary-UUID--
```

### Response

```json
{
  "text": "The transcribed text goes here."
}
```

---

## Configuration in MarsinDictation

### Via Settings UI (Recommended)

Click the **mic icon** in the menu bar → **Settings...**:
- **Provider**: LocalAI (default)
- **Endpoint**: `http://localhost:3850`
- **Model**: `whisper-1`

### Via .env (Development)

```bash
MARSIN_TRANSCRIPTION_PROVIDER=localai
LOCALAI_ENDPOINT=http://localhost:3850
LOCALAI_MODEL=whisper-1
MARSIN_LANGUAGE=en
```

### Priority Order

1. **In-app Settings** (UserDefaults) — takes priority
2. **Environment variables** (`.env` file) — fallback for development
3. **Hardcoded defaults** — `localai`, `localhost:3850`, `whisper-1`, `en`

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Transcription failed" | Check `curl http://localhost:3850/v1/models` — is LocalAI running? |
| Slow transcription | Try a smaller model (`whisper-small`) or check CPU/GPU load |
| Wrong language | Set language in Settings or `.env` (`MARSIN_LANGUAGE=en`) |
| Model not found | Run `local-ai run whisper-1` to download it |
| Port conflict | Change port: `local-ai run --address :3841` and update endpoint in Settings |

---

## Future Considerations

- **GPU acceleration**: LocalAI supports CUDA/Metal backends for faster inference
- **Streaming transcription**: Not supported by Whisper, but future models may enable real-time partial results
- **Model auto-download**: Consider bundling model download into `deploy.py` setup
- **Ollama**: Out of scope for v0 — its primary APIs are text-generation, not audio transcription
