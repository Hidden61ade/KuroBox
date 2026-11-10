"""Prepare selected supplied assets and the isolated Godot conversion script.

This script does not modify game rules or project settings. The core boxing artwork is authored separately through Aseprite MCP;
this tool only prepares supplied packs and the original short hit sound.
"""
from pathlib import Path
import json
import zipfile
import math
import random
import struct
import wave
import subprocess
import argparse
import shutil

ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = Path.home() / "Downloads"


def extract_member(archive, member, destination):
    with zipfile.ZipFile(archive) as package:
        payload = package.read(member)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)

def synthesize_thud(destination):
    rng = random.Random(42)
    rate = 44100
    smooth = 0.0
    samples = []
    for index in range(int(rate * 0.16)):
        time = index / rate
        noise = rng.uniform(-1, 1)
        smooth = 0.72 * smooth + 0.28 * noise
        envelope = math.exp(-time * 38)
        click = noise * math.exp(-time * 180) * 0.32
        tone = math.sin(2 * math.pi * (105 * time - 120 * time * time)) * envelope * 0.6
        sample = (tone + smooth * envelope * 0.34 + click) * min(1, time / 0.001)
        samples.append(max(-32767, min(32767, int(sample * 26000))))
    with wave.open(str(destination), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(struct.pack("<" + "h" * len(samples), *samples))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--downloads", type=Path, default=DOWNLOADS)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    args = parser.parse_args()
    downloads = args.downloads
    selected = {
        "ui_confirm": "Minimalist1",
        "ui_back": "Minimalist2",
        "place": "Wood Block1",
        "undo": "Minimalist5",
        "goal": "Retro12",
        "wood_contact": "Wood Block2",
    }
    for event, source in selected.items():
        extract_member(downloads / "UI Soundpack.zip", f"UI Soundpack/OGG/{source}.ogg", ROOT / f"assets/audio/{event}.ogg")
    extract_member(downloads / "UI Soundpack.zip", "UI Soundpack/readme.txt", ROOT / "assets/audio/UI_Soundpack_LICENSE.txt")
    synthesize_thud(ROOT / "assets/audio/punch_thud.wav")
    if not args.ffmpeg:
        raise FileNotFoundError("Pass --ffmpeg with an installed FFmpeg executable.")
    encoder = Path(args.ffmpeg)
    if not encoder.is_file():
        raise FileNotFoundError(encoder)
    subprocess.run([str(encoder), "-hide_banner", "-loglevel", "error", "-y", "-i", str(ROOT / "assets/audio/punch_thud.wav"), "-c:a", "libvorbis", "-q:a", "5", str(ROOT / "assets/audio/punch.ogg")], check=True)
    extract_member(downloads / "Effect.zip", "Effect/sheets/32x32.png", ROOT / "assets/effects/supplied_effects_32.png")
    extract_member(downloads / "ASSET_v0.2.zip", "ASSET/sheet/items.png", ROOT / "assets/ui/supplied_items.png")

    print("Prepared the supplied images, UI sounds, and original hit sound.")

if __name__ == "__main__":
    main()
