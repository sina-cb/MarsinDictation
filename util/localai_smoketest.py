#!/usr/bin/env python3
"""
LocalAI Smoke Test — verifies the LocalAI instance is reachable and
can transcribe audio via the Whisper model.

Usage:
    python util/localai_smoketest.py
    python util/localai_smoketest.py --endpoint http://localhost:3850
    python util/localai_smoketest.py --wav path/to/audio.wav

Tests performed:
    1. Health check       — GET /readyz
    2. List models        — GET /v1/models
    3. Transcribe audio   — POST /v1/audio/transcriptions (FirstHello.wav)
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error
import time
import mimetypes

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_WAV = os.path.join(
    REPO_ROOT, "windows", "MarsinDictation.Tests", "TestData", "FirstHello.wav"
)
DEFAULT_ENDPOINT = "http://localhost:3850"
DEFAULT_MODEL = "whisper-1"


# ── Helpers ──────────────────────────────────────────────────

def ok(label: str, detail: str = ""):
    print(f"  ✔ {label}" + (f"  ({detail})" if detail else ""))


def fail(label: str, detail: str = ""):
    print(f"  ✗ {label}" + (f"  ({detail})" if detail else ""))


def section(title: str):
    print(f"\n{'─' * 50}")
    print(f"  {title}")
    print(f"{'─' * 50}")


def build_multipart(fields: dict, files: dict) -> tuple[bytes, str]:
    """Build a multipart/form-data body from fields and files dicts.
    
    fields: {name: value} — string fields
    files:  {name: (filename, data, content_type)} — file fields
    
    Returns (body_bytes, content_type_header).
    """
    boundary = "----MarsinSmokeTestBoundary"
    parts = []

    for name, value in fields.items():
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        parts.append(f"{value}\r\n".encode())

    for name, (filename, data, content_type) in files.items():
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(
            f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode()
        )
        parts.append(f"Content-Type: {content_type}\r\n\r\n".encode())
        parts.append(data)
        parts.append(b"\r\n")

    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    content_type = f"multipart/form-data; boundary={boundary}"
    return body, content_type


# ── Tests ────────────────────────────────────────────────────

def test_health(endpoint: str) -> bool:
    """Test 1: GET /readyz — health check."""
    section("Test 1: Health Check  (GET /readyz)")
    try:
        r = urllib.request.urlopen(f"{endpoint}/readyz", timeout=10)
        if r.status == 200:
            ok("LocalAI is healthy", f"HTTP {r.status}")
            return True
        else:
            fail("Unexpected status", f"HTTP {r.status}")
            return False
    except urllib.error.URLError as e:
        fail("Cannot reach LocalAI", str(e.reason))
        print(f"\n  💡 Is LocalAI running at {endpoint}?")
        print(f"     Check: curl {endpoint}/readyz")
        return False
    except Exception as e:
        fail("Health check error", str(e))
        return False


def test_models(endpoint: str, expected_model: str) -> bool:
    """Test 2: GET /v1/models — list available models."""
    section("Test 2: List Models  (GET /v1/models)")
    try:
        r = urllib.request.urlopen(f"{endpoint}/v1/models", timeout=10)
        body = json.loads(r.read())
        models = [m.get("id", "?") for m in body.get("data", [])]
        print(f"  📋 Available models: {models}")

        if expected_model in models:
            ok(f"Expected model '{expected_model}' is available")
            return True
        else:
            fail(f"Expected model '{expected_model}' NOT found")
            print(f"  💡 Available models: {models}")
            return False
    except Exception as e:
        fail("Failed to list models", str(e))
        return False


def test_transcribe(endpoint: str, model: str, wav_path: str) -> bool:
    """Test 3: POST /v1/audio/transcriptions — transcribe audio file."""
    section("Test 3: Transcribe Audio  (POST /v1/audio/transcriptions)")

    if not os.path.exists(wav_path):
        fail("WAV file not found", wav_path)
        print(f"  💡 Record one: python util/record.py {wav_path}")
        return False

    wav_data = open(wav_path, "rb").read()
    wav_size = len(wav_data)
    print(f"  📁 File: {os.path.basename(wav_path)} ({wav_size:,} bytes)")

    body, content_type = build_multipart(
        fields={"model": model},
        files={"file": ("audio.wav", wav_data, "audio/wav")},
    )

    req = urllib.request.Request(
        f"{endpoint}/v1/audio/transcriptions",
        data=body,
        headers={"Content-Type": content_type},
        method="POST",
    )

    start = time.time()
    try:
        r = urllib.request.urlopen(req, timeout=120)
        elapsed = time.time() - start
        result = json.loads(r.read())
        text = result.get("text", "").strip()

        if text:
            ok(f"Transcription received", f"{elapsed:.1f}s")
            print(f"\n  📝 Result: \"{text}\"\n")

            # Check if it sounds like "Hello World"
            lower = text.lower()
            if "hello" in lower:
                ok("Transcription contains 'hello' — content looks correct")
            else:
                print(f"  ⚠ Expected 'hello' in transcription (got: \"{text}\")")
                print(f"    This may be OK if the WAV contains different speech.")

            return True
        else:
            fail("Transcription returned empty text")
            print(f"  💡 The audio may be too short or contain only silence")
            return False

    except urllib.error.HTTPError as e:
        elapsed = time.time() - start
        error_body = e.read().decode(errors="replace")
        fail(f"HTTP {e.code}", f"{elapsed:.1f}s")
        print(f"  Response: {error_body[:500]}")
        return False
    except Exception as e:
        elapsed = time.time() - start
        fail(f"Transcription error", f"{elapsed:.1f}s — {e}")
        return False


# ── Main ─────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="LocalAI smoke test for MarsinDictation")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT,
                        help=f"LocalAI base URL (default: {DEFAULT_ENDPOINT})")
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help=f"Whisper model name (default: {DEFAULT_MODEL})")
    parser.add_argument("--wav", default=DEFAULT_WAV,
                        help=f"WAV file to transcribe (default: TestData/FirstHello.wav)")
    args = parser.parse_args()

    print(f"🔬 LocalAI Smoke Test")
    print(f"   Endpoint: {args.endpoint}")
    print(f"   Model:    {args.model}")
    print(f"   WAV:      {args.wav}")

    results = {}

    # Test 1: Health
    results["health"] = test_health(args.endpoint)
    if not results["health"]:
        print(f"\n❌ FAILED — LocalAI is not reachable at {args.endpoint}")
        print(f"   Cannot proceed with remaining tests.")
        sys.exit(1)

    # Test 2: Models
    results["models"] = test_models(args.endpoint, args.model)

    # Test 3: Transcribe
    results["transcribe"] = test_transcribe(args.endpoint, args.model, args.wav)

    # Summary
    section("Summary")
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    for name, ok_flag in results.items():
        status = "✔ PASS" if ok_flag else "✗ FAIL"
        print(f"  {status}  {name}")
    print()

    if passed == total:
        print(f"🎉 All {total} tests passed — LocalAI is ready for MarsinDictation!")
        sys.exit(0)
    else:
        print(f"⚠  {passed}/{total} tests passed — check failures above")
        sys.exit(1)


if __name__ == "__main__":
    main()
