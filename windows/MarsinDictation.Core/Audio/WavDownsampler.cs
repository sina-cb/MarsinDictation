using Microsoft.Extensions.Logging;

namespace MarsinDictation.Core.Audio;

/// <summary>
/// Downsamples a WAV byte array from the WASAPI capture format
/// (48kHz, 32-bit float, stereo) to Whisper's preferred format
/// (16kHz, 16-bit PCM, mono).
///
/// This reduces a 60-second recording from ~24 MB to ~1.9 MB,
/// preventing LocalAI body-size rejections and speeding up uploads.
/// </summary>
public static class WavDownsampler
{
    /// <summary>
    /// Downsample a WAV byte array to 16kHz/16-bit/mono.
    /// Returns a new WAV byte array, or the original if already compatible.
    /// </summary>
    public static byte[] Downsample(byte[] wavData, ILogger? logger = null)
    {
        if (wavData.Length < 44)
            return wavData; // Too small to be a valid WAV

        // ── Parse WAV header ────────────────────────────────
        // Standard WAV layout: RIFF header (12) + fmt chunk (24+) + data chunk
        var riffId = System.Text.Encoding.ASCII.GetString(wavData, 0, 4);
        var waveId = System.Text.Encoding.ASCII.GetString(wavData, 8, 4);
        if (riffId != "RIFF" || waveId != "WAVE")
        {
            logger?.LogWarning("WavDownsampler: not a valid WAV file, skipping");
            return wavData;
        }

        // Find fmt chunk
        int pos = 12;
        ushort audioFormat = 0, channels = 0, bitsPerSample = 0;
        uint sampleRate = 0;
        int fmtFound = -1;

        while (pos + 8 <= wavData.Length)
        {
            var chunkId = System.Text.Encoding.ASCII.GetString(wavData, pos, 4);
            var chunkSize = BitConverter.ToInt32(wavData, pos + 4);

            if (chunkId == "fmt ")
            {
                fmtFound = pos;
                audioFormat = BitConverter.ToUInt16(wavData, pos + 8);
                channels = BitConverter.ToUInt16(wavData, pos + 10);
                sampleRate = BitConverter.ToUInt32(wavData, pos + 12);
                bitsPerSample = BitConverter.ToUInt16(wavData, pos + 22);
                pos += 8 + chunkSize;
                break;
            }
            pos += 8 + chunkSize;
            if (chunkSize % 2 != 0) pos++; // WAV chunks are word-aligned
        }

        if (fmtFound < 0)
        {
            logger?.LogWarning("WavDownsampler: no fmt chunk found, skipping");
            return wavData;
        }

        // Find data chunk
        int dataOffset = -1;
        int dataSize = 0;
        while (pos + 8 <= wavData.Length)
        {
            var chunkId = System.Text.Encoding.ASCII.GetString(wavData, pos, 4);
            var chunkSize = BitConverter.ToInt32(wavData, pos + 4);

            if (chunkId == "data")
            {
                dataOffset = pos + 8;
                dataSize = chunkSize;
                break;
            }
            pos += 8 + chunkSize;
            if (chunkSize % 2 != 0) pos++;
        }

        if (dataOffset < 0 || dataOffset + dataSize > wavData.Length)
        {
            logger?.LogWarning("WavDownsampler: no data chunk found, skipping");
            return wavData;
        }

        // ── Check if downsampling is needed ─────────────────
        // IEEE float = 3, PCM = 1
        bool isFloat = audioFormat == 3;
        bool isPcm = audioFormat == 1;

        if (!isFloat && !isPcm)
        {
            logger?.LogWarning("WavDownsampler: unsupported audio format {Format}, skipping", audioFormat);
            return wavData;
        }

        // Already at target format?
        if (sampleRate == 16000 && channels == 1 && bitsPerSample == 16 && isPcm)
        {
            logger?.LogDebug("WavDownsampler: already at target format, no conversion needed");
            return wavData;
        }

        // ── Convert to float samples ────────────────────────
        int bytesPerSample = bitsPerSample / 8;
        int blockAlign = bytesPerSample * channels;
        int totalFrames = dataSize / blockAlign;

        // Read all samples as float (mono-mixed)
        var monoSamples = new float[totalFrames];

        for (int i = 0; i < totalFrames; i++)
        {
            int frameOffset = dataOffset + i * blockAlign;
            float sum = 0;

            for (int ch = 0; ch < channels; ch++)
            {
                int sampleOffset = frameOffset + ch * bytesPerSample;
                if (sampleOffset + bytesPerSample > wavData.Length) break;

                float sample;
                if (isFloat && bitsPerSample == 32)
                {
                    sample = BitConverter.ToSingle(wavData, sampleOffset);
                }
                else if (isPcm && bitsPerSample == 16)
                {
                    sample = BitConverter.ToInt16(wavData, sampleOffset) / 32768f;
                }
                else if (isPcm && bitsPerSample == 24)
                {
                    int val = wavData[sampleOffset]
                            | (wavData[sampleOffset + 1] << 8)
                            | (wavData[sampleOffset + 2] << 16);
                    if ((val & 0x800000) != 0) val |= unchecked((int)0xFF000000); // sign extend
                    sample = val / 8388608f;
                }
                else
                {
                    sample = 0;
                }
                sum += sample;
            }
            monoSamples[i] = sum / channels;
        }

        // ── Resample to 16kHz ───────────────────────────────
        const uint targetRate = 16000;
        double ratio = (double)sampleRate / targetRate;
        int outputFrames = (int)(totalFrames / ratio);

        var outputSamples = new short[outputFrames];
        for (int i = 0; i < outputFrames; i++)
        {
            // Simple linear interpolation
            double srcPos = i * ratio;
            int srcIdx = (int)srcPos;
            double frac = srcPos - srcIdx;

            float val;
            if (srcIdx + 1 < totalFrames)
            {
                val = (float)(monoSamples[srcIdx] * (1.0 - frac) + monoSamples[srcIdx + 1] * frac);
            }
            else
            {
                val = monoSamples[Math.Min(srcIdx, totalFrames - 1)];
            }

            // Clamp and convert to 16-bit PCM
            val = Math.Clamp(val, -1.0f, 1.0f);
            outputSamples[i] = (short)(val * 32767);
        }

        // ── Write output WAV ────────────────────────────────
        int outDataSize = outputFrames * 2; // 16-bit mono = 2 bytes per sample
        int outFileSize = 44 + outDataSize;  // Standard WAV header = 44 bytes
        var output = new byte[outFileSize];

        // RIFF header
        WriteString(output, 0, "RIFF");
        WriteInt32(output, 4, outFileSize - 8);
        WriteString(output, 8, "WAVE");

        // fmt chunk
        WriteString(output, 12, "fmt ");
        WriteInt32(output, 16, 16);         // chunk size
        WriteUInt16(output, 20, 1);         // PCM format
        WriteUInt16(output, 22, 1);         // mono
        WriteUInt32(output, 24, targetRate);
        WriteUInt32(output, 28, targetRate * 2); // byte rate
        WriteUInt16(output, 32, 2);         // block align
        WriteUInt16(output, 34, 16);        // bits per sample

        // data chunk
        WriteString(output, 36, "data");
        WriteInt32(output, 40, outDataSize);

        // Write samples
        for (int i = 0; i < outputFrames; i++)
        {
            var bytes = BitConverter.GetBytes(outputSamples[i]);
            output[44 + i * 2] = bytes[0];
            output[44 + i * 2 + 1] = bytes[1];
        }

        logger?.LogInformation(
            "WavDownsampler: {InRate}Hz/{InBits}bit/{InCh}ch ({InSize:N0} B) → {OutRate}Hz/16bit/mono ({OutSize:N0} B) — {Ratio:F1}x reduction",
            sampleRate, bitsPerSample, channels, wavData.Length, targetRate, output.Length,
            (double)wavData.Length / output.Length);

        return output;
    }

    private static void WriteString(byte[] buf, int offset, string s)
    {
        for (int i = 0; i < s.Length; i++)
            buf[offset + i] = (byte)s[i];
    }

    private static void WriteInt32(byte[] buf, int offset, int value)
    {
        var bytes = BitConverter.GetBytes(value);
        Array.Copy(bytes, 0, buf, offset, 4);
    }

    private static void WriteUInt16(byte[] buf, int offset, ushort value)
    {
        var bytes = BitConverter.GetBytes(value);
        Array.Copy(bytes, 0, buf, offset, 2);
    }

    private static void WriteUInt32(byte[] buf, int offset, uint value)
    {
        var bytes = BitConverter.GetBytes(value);
        Array.Copy(bytes, 0, buf, offset, 4);
    }
}
