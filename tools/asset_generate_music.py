"""Generate KuroBox's original 20-second loop with Python's standard library.

No recordings or existing melodies are used. Notes and decays are wrapped into
the same periodic buffer so tails continue across the loop boundary.
"""
from array import array
from pathlib import Path
import argparse
import json
import math
import subprocess
import sys
import wave

RATE = 44100
BPM = 96
BEAT = 60.0 / BPM
SECONDS = 32 * BEAT
COUNT = round(SECONDS * RATE)
ROOT = Path(__file__).resolve().parents[1]
TAU = math.tau

def frequency(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)

def add_note(left, right, start, midi, duration, gain, pan=0.0, kind="key"):
    onset = round(start * RATE)
    frames = round(duration * RATE)
    pitch = frequency(midi)
    left_gain = math.sqrt((1.0 - pan) * 0.5)
    right_gain = math.sqrt((1.0 + pan) * 0.5)
    attack = 0.012 if kind != "pad" else 0.07
    release = 0.12 if kind != "pad" else 0.5
    for index in range(frames):
        time = index / RATE
        fade_in = min(1.0, time / attack)
        fade_out = min(1.0, (duration - time) / release)
        envelope = math.sin(fade_in * math.pi / 2) ** 2 * math.sin(fade_out * math.pi / 2) ** 2
        phase = TAU * pitch * time
        if kind == "bass":
            envelope *= math.exp(-time * 2.4)
            tone = math.sin(phase) + 0.22 * math.sin(phase * 2) + 0.055 * math.sin(phase * 3)
        elif kind == "pad":
            envelope *= 0.78 + 0.22 * math.cos(TAU * time / duration)
            tone = math.sin(phase) + 0.12 * math.sin(phase * 2)
        else:
            envelope *= math.exp(-time * 3.6)
            tone = math.sin(phase) + 0.16 * math.sin(phase * 2) * math.exp(-time * 8)
        sample = gain * envelope * tone
        target = (onset + index) % COUNT
        left[target] += sample * left_gain
        right[target] += sample * right_gain

def add_tap(left, right, start, gain, low=False, pan=0.0):
    onset = round(start * RATE)
    duration = 0.18 if low else 0.085
    frames = round(duration * RATE)
    for index in range(frames):
        time = index / RATE
        envelope = min(1.0, time / 0.003) * min(1.0, (duration - time) / 0.025)
        envelope *= math.exp(-time * (28 if low else 65))
        if low:
            phase = TAU * (72 * time + 0.42 * (1 - math.exp(-time * 45)))
            tone = math.sin(phase) + 0.1 * math.sin(2 * phase)
        else:
            tone = math.sin(TAU * 390 * time) * 0.8 + math.sin(TAU * 585 * time) * 0.2
        sample = gain * tone * envelope
        target = (onset + index) % COUNT
        left[target] += sample * math.sqrt((1 - pan) * 0.5)
        right[target] += sample * math.sqrt((1 + pan) * 0.5)

def write_wav(path, left, right):
    # A 22 ms cosine join leaves value and slope at zero on both ends. This
    # also gives the lossy encoder a quiet, click-resistant loop junction.
    join_frames = round(0.022 * RATE)
    for index in range(join_frames):
        gain = 0.5 - 0.5 * math.cos(math.pi * index / join_frames)
        for channel in (left, right):
            channel[index] *= gain
            channel[-1-index] *= gain
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
    scale = 0.54 / peak
    pcm = array("h")
    energy = 0.0
    for a, b in zip(left, right):
        for value in (a, b):
            value *= scale
            energy += value * value
            pcm.append(max(-32767, min(32767, round(value * 32767))))
    if sys.byteorder != "little":
        pcm.byteswap()
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    jumps = [abs(left[-1] - left[0]) * scale, abs(right[-1] - right[0]) * scale]
    return {"duration_seconds": SECONDS, "sample_rate": RATE, "channels": 2, "peak": 0.54, "rms": math.sqrt(energy / (COUNT * 2)), "boundary_adjacent_sample_delta": max(jumps), "periodic_tail_wrapping": True, "cosine_join_milliseconds_each_side": 22}

def inspect_wav(path):
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        frames = source.getnframes()
        rate = source.getframerate()
        values = array("h", source.readframes(frames))
    if sys.byteorder != "little":
        values.byteswap()
    return {"duration_seconds": frames / rate, "peak": max(abs(value) for value in values) / 32768, "rms": math.sqrt(sum((value / 32768) ** 2 for value in values) / len(values)), "boundary_adjacent_sample_delta": max(abs(values[channel] - values[-channels + channel]) / 32768 for channel in range(channels))}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", type=Path, default=Path(r"C:\Program Files\Derivative\TouchDesigner\bin\ffmpeg.exe"))
    args = parser.parse_args()
    if not args.ffmpeg.is_file():
        parser.error("Pass the existing local FFmpeg executable with --ffmpeg")
    left, right = array("d", [0.0]) * COUNT, array("d", [0.0]) * COUNT
    # Four original two-bar voicings; the upper line stays below B4.
    harmony = [(38, [50, 53, 57, 64], [69, 65, 64, 62]),
               (43, [55, 59, 62, 64], [59, 62, 64, 62]),
               (36, [48, 52, 55, 59], [64, 67, 71, 67]),
               (33, [45, 48, 52, 55], [64, 60, 59, 60])]
    for phrase, (bass, chord, melody) in enumerate(harmony):
        base = phrase * 8 * BEAT
        for offset in (0.0, 4.0):
            for voice, midi in enumerate(chord):
                add_note(left, right, base + offset * BEAT + voice * 0.014, midi, 3.1, 0.043, (voice - 1.5) * 0.15, "pad")
        for offset, midi in [(0, bass), (3, bass + 7), (4.5, bass + 12), (6.5, bass + 7)]:
            add_note(left, right, base + offset * BEAT, midi, 0.55, 0.20, kind="bass")
        for offset, midi in zip((1.5, 3.5, 5.0, 7.5), melody):
            add_note(left, right, base + offset * BEAT, midi, 0.68, 0.075, -0.12 if phrase % 2 else 0.12)
    for bar in range(8):
        base = bar * 4 * BEAT
        add_tap(left, right, base, 0.11, low=True)
        add_tap(left, right, base + 2 * BEAT, 0.052, pan=-0.15)
        if bar % 2:
            add_tap(left, right, base + 3.5 * BEAT, 0.033, pan=0.15)
    work = ROOT / ".tools/music_generation"
    work.mkdir(parents=True, exist_ok=True)
    source = work / "music_source.wav"
    output = ROOT / "assets/audio/music.ogg"
    decoded = work / "music_decoded.wav"
    info = write_wav(source, left, right)
    subprocess.run([str(args.ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-i", str(source), "-c:a", "libvorbis", "-q:a", "5", str(output)], check=True)
    subprocess.run([str(args.ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-i", str(output), "-c:a", "pcm_s16le", str(decoded)], check=True)
    info["decoded_ogg"] = inspect_wav(decoded)
    info["subjective_listening_review"] = "not_performed"
    info["source"] = "Original procedural composition; no third-party recordings or copied melody."
    if info["decoded_ogg"]["peak"] > 0.65:
        raise RuntimeError("Encoded peak exceeds the agreed limit")
    if info["decoded_ogg"]["boundary_adjacent_sample_delta"] > 0.001:
        raise RuntimeError("Encoded loop boundary exceeds the click check threshold")
    (work / "music_metrics.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    print(json.dumps(info, indent=2))

if __name__ == "__main__":
    main()
