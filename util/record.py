#!/usr/bin/env python3
"""
Record audio from the default microphone and save as WAV.

Usage:
    python util/record.py <output_path> [--duration SECONDS]

Examples:
    python util/record.py windows/MarsinDictation.Tests/TestData/test_audio.wav
    python util/record.py tmp/test.wav --duration 3

If --duration is omitted, recording continues until you press ENTER.
"""

import os
import sys
import argparse
import wave
import threading

def main():
    parser = argparse.ArgumentParser(description="Record audio from mic → WAV file")
    parser.add_argument("output", help="Output WAV file path")
    parser.add_argument("--duration", type=float, default=None,
                        help="Record for N seconds (default: press ENTER to stop)")
    parser.add_argument("--rate", type=int, default=16000,
                        help="Sample rate in Hz (default: 16000)")
    args = parser.parse_args()

    # Auto-install sounddevice + numpy if missing
    try:
        import sounddevice as sd
        import numpy as np
    except ImportError:
        print("Installing sounddevice + numpy...")
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "sounddevice", "numpy"],
                              stdout=subprocess.DEVNULL)
        import sounddevice as sd
        import numpy as np

    samplerate = args.rate
    channels = 1
    frames = []
    stop_event = threading.Event()

    def callback(indata, frame_count, time_info, status):
        if status:
            print(f"  ⚠ {status}", file=sys.stderr)
        frames.append(indata.copy())

    # Ensure output directory exists
    out_dir = os.path.dirname(os.path.abspath(args.output))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    print(f"🎙  Recording to: {os.path.abspath(args.output)}")
    print(f"    Format: WAV, {samplerate} Hz, mono, 16-bit")

    if args.duration:
        print(f"    Duration: {args.duration}s")
        print()
        recording = sd.rec(int(args.duration * samplerate),
                          samplerate=samplerate, channels=channels, dtype="int16")
        sd.wait()
        frames_data = recording
    else:
        print(f"    Press ENTER to stop...")
        print()
        with sd.InputStream(samplerate=samplerate, channels=channels,
                           dtype="int16", callback=callback):
            input()
        if not frames:
            print("✗  No audio captured")
            sys.exit(1)
        frames_data = np.concatenate(frames)

    # Save WAV
    abs_path = os.path.abspath(args.output)
    with wave.open(abs_path, "w") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(2)  # 16-bit = 2 bytes
        wf.setframerate(samplerate)
        wf.writeframes(frames_data.tobytes())

    duration = len(frames_data) / samplerate
    size = os.path.getsize(abs_path)
    print(f"✔  Saved: {abs_path}")
    print(f"   {duration:.1f}s, {size:,} bytes")

if __name__ == "__main__":
    main()
