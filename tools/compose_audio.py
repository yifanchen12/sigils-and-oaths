"""Render the original game compositions and effects into Godot-ready files."""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import subprocess
import tempfile
import wave

import numpy as np


RATE = 32_000
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
TAU = math.tau


def sine(freq: float, time: np.ndarray) -> np.ndarray:
    return np.sin(TAU * freq * time)


def envelope(time: np.ndarray, length: float, attack: float, release: float) -> np.ndarray:
    return np.clip(time / attack, 0, 1) * np.clip((length - time) / release, 0, 1)


def pitch(note: int) -> float:
    return 440 * 2 ** ((note - 69) / 12)


def place(mix: np.ndarray, voice: np.ndarray, onset: float, pan: float) -> None:
    start = round(onset * RATE)
    rows = (start + np.arange(len(voice))) % len(mix)
    mix[rows, 0] += voice * math.sqrt(0.5 - pan * 0.5)
    mix[rows, 1] += voice * math.sqrt(0.5 + pan * 0.5)


def add_note(mix: np.ndarray, style: str, note: int, onset: float, duration: float, gain: float, pan: float) -> None:
    time = np.arange(round(duration * RATE)) / RATE
    freq = pitch(note)
    if style == "pluck":
        partials = zip((1, 2.003, 3.008, 4.02), (1, 0.46, 0.22, 0.09), (2.4, 5.8, 9.1, 13))
        voice = sum(gain * formant * sine(freq * ratio, time) * np.exp(-decay * time) for ratio, formant, decay in partials)
        voice *= envelope(time, duration, 0.012, 0.19)
    elif style == "reed":
        carrier = TAU * freq * time + 0.095 * sine(4.7, time)
        voice = gain * (np.sin(carrier) + 0.19 * np.sin(2 * carrier) + 0.11 * np.sin(3 * carrier))
        voice *= envelope(time, duration, 0.20, 0.36)
    else:
        voice = gain * (sine(freq, time) + 0.5 * sine(freq * 1.002, time) + 0.15 * sine(freq * 2, time))
        voice *= envelope(time, duration, 0.64, 0.88)
    place(mix, voice, onset, pan)
    place(mix, voice * 0.14, onset + 0.27, -pan)
    place(mix, voice * 0.065, onset + 0.49, pan * 0.4)


COUNCIL_MELODY = (
    (0, 2, 0, -1), (-3, -1, 0, 2), (4, 3, 2, 0), (-1, None, -3, None),
    (0, 2, 4, 6), (3, 4, 2, None), (2, 0, -1, -3), (-4, None, -2, None),
    (-2, 0, 3, 2), (4, 3, 0, None), (2, 4, 5, 2), (0, -1, 0, None),
    (4, 2, 0, -1), (3, 2, 0, None), (0, -3, -2, -1), (-3, None, None, None),
)
BATTLE_MELODY = (
    (0, 0, 2, 3), (2, 0, -1, 0), (4, 3, 2, -1), (-2, None, 0, 3),
    (5, 4, 3, 2), (0, -1, 0, 2), (2, 0, -2, -1), (0, None, None, 2),
    (4, 4, 5, 7), (6, 5, 4, 3), (3, 2, 0, 2), (-1, None, -2, 0),
    (0, 2, 3, 4), (4, 5, 4, 2), (3, 2, 0, -1), (0, None, None, 3),
    (5, 4, 2, 3), (2, 2, 0, -1), (-2, 0, 2, 4), (3, 2, 0, 2),
    (3, 5, 4, 2), (2, 0, -1, -2), (-1, 2, 0, -1), (0, None, None, None),
)
SCALE = (0, 2, 3, 5, 7, 9, 10)


def degree(index: int, base: int) -> int:
    octave, step = divmod(index, len(SCALE))
    return base + 12 * octave + SCALE[step]


def texture(length: float, kind: str, seed: int) -> np.ndarray:
    time = np.arange(round(RATE * length)) / RATE
    rng = np.random.default_rng(seed)
    noise = rng.normal(0, 1, len(time))
    soft_noise = np.convolve(noise, np.hanning(25) / np.hanning(25).sum(), mode="same")
    if kind == "tap":
        voice = 0.70 * sine(148, time) * np.exp(-16 * time) + 0.36 * soft_noise * np.exp(-24 * time)
    elif kind == "clash":
        voice = (0.40 * sine(178, time) + 0.26 * sine(871, time) + 0.23 * sine(1331, time)) * np.exp(-17 * time) + 0.61 * soft_noise * np.exp(-12 * time)
    elif kind == "snap":
        voice = (0.45 * noise + 0.34 * sine(192, time)) * np.exp(-33 * time)
    else:
        voice = (soft_noise * 0.8 + np.sin(TAU * (172 * time + 330 * time * time)) * 0.25) * np.power(np.sin(np.pi * time / length), 1.7)
    return voice * envelope(time, length, 0.009, 0.045)


def composition(battle: bool) -> np.ndarray:
    melody = BATTLE_MELODY if battle else COUNCIL_MELODY
    beat = 60 / (98 if battle else 62)
    mix = np.zeros((round(len(melody) * 4 * beat * RATE), 2), dtype=np.float64)
    song_root = 62
    roots = (0, -2, -3, -1, 0, -2, 2, -3, -1, -3, -2, 0)
    for bar, phrase in enumerate(melody):
        onset = bar * 4 * beat
        root = roots[bar % len(roots)]
        for chord_degree in (root, root + 4, root + 7):
            add_note(mix, "pad", degree(chord_degree, song_root - 24), onset - beat * 0.12, beat * 4.1, 0.059, 0.12)
        for slot, offset in enumerate(phrase):
            if offset is None:
                continue
            start = onset + (slot * (0.88 if battle else 0.94) + 0.23) * beat
            style = "reed" if (not battle and bar % 4 in (1, 2) and slot % 2 == 0) else "pluck"
            add_note(mix, style, degree(offset, song_root + (0 if battle else 12)), start, (1.55 if style == "reed" else 1.12) * beat, 0.105 if style == "reed" else 0.24, -0.36 if slot % 2 == 0 else 0.23)
        if battle:
            for slot in (0, 1.5, 2.5):
                place(mix, texture(0.28, "tap", bar * 19 + round(slot * 2)) * (0.32 if slot == 0 else 0.11), onset + beat * slot, -0.16)
                add_note(mix, "pluck", degree(root + (4 if slot == 1.5 else 0), song_root - 12), onset + beat * (slot + 0.27), beat * 1.34, 0.15, 0.46)
        else:
            add_note(mix, "pluck", degree(root + 4, song_root), onset + beat * 2.9, beat * 1.1, 0.14, 0.46)
    return mix


def write_wav(path: Path, mix: np.ndarray, peak: float) -> None:
    scale = peak / max(0.001, np.max(np.abs(mix)))
    frames = np.asarray(mix * scale * 32767, dtype="<i2")
    with wave.open(str(path), "wb") as output:
        output.setparams((2, 2, RATE, len(mix), "NONE", "not compressed"))
        output.writeframes(frames.tobytes())


def render_music() -> None:
    with tempfile.TemporaryDirectory(prefix="sigils-audio-") as temporary:
        for scene in ("council", "battle"):
            intermediate = Path(temporary) / (scene + ".wav")
            write_wav(intermediate, composition(scene == "battle"), 0.36)
            subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(intermediate),
                            "-c:a", "libvorbis", "-q:a", "4", str(OUTPUT / (scene + ".ogg"))], check=True)

def render_cues(signatures_only: bool) -> None:
    cues = {
        "move": (0.36, "tap", ((0.00, 0.65, -0.20), (0.12, 0.37, 0.18)), ()),
        "deploy": (0.64, "tap", ((0.00, 0.21, 0.10),), ((0.08, 58), (0.18, 65))),
        "attack": (0.50, "clash", ((0.06, 0.57, -0.16), (0.17, 0.19, 0.21)), ()),
        "cast": (0.76, "wash", ((0.00, 0.36, -0.14),), ((0.19, 62), (0.24, 69), (0.31, 74))),
        "guard": (0.62, "clash", ((0.02, 0.15, 0.06),), ((0.08, 53), (0.10, 60))),
        "trap": (0.62, "snap", ((0.07, 0.54, -0.16), (0.19, 0.32, 0.18)), ((0.15, 45),)),
        "turn": (0.80, "tap", (), ((0.00, 69), (0.12, 74))),
        "victory": (1.86, "tap", (), ((0.02, 62), (0.25, 65), (0.44, 69), (0.68, 74), (0.70, 77))),
        "defeat": (1.78, "wash", ((0.00, 0.09, -0.10),), ((0.05, 62), (0.30, 57), (0.60, 50))),
        "bulwark": (0.79, "clash", ((0.06, 0.11, -0.20), (0.33, 0.49, 0.05)), ((0.10, 53), (0.33, 60), (0.38, 65))),
        "comet": (0.86, "wash", ((0.03, 0.37, -0.19), (0.24, 0.66, 0.18)), ((0.06, 81), (0.20, 70), (0.41, 43))),
        "willow": (0.90, "wash", ((0.13, 0.15, -0.22),), ((0.08, 69), (0.21, 74), (0.35, 76), (0.48, 81))),
    }
    for index, (name, (length, kind, hits, notes)) in enumerate(cues.items()):
        if signatures_only and name not in {"bulwark", "comet", "willow"}:
            continue
        mix = np.zeros((round(RATE * length), 2), dtype=np.float64)
        for onset, gain, pan in hits:
            duration = min(0.36, length - onset - 0.02)
            place(mix, texture(duration, kind, 41 + index * 7 + int(onset * 100)) * gain, onset, pan)
        for onset, note in notes:
            # Render dry cues, then apply a short fade before their end.
            duration = min(0.72, length - onset - 0.03)
            time = np.arange(round(RATE * duration)) / RATE
            tone = (sine(pitch(note), time) + 0.24 * sine(pitch(note) * 2, time)) * np.exp(-4.8 * time)
            place(mix, tone * envelope(time, duration, 0.018, 0.14) * 0.24, onset, -0.20 if note % 2 else 0.14)
        write_wav(OUTPUT / (name + ".wav"), mix, 0.39 if name in ("attack", "trap", "victory", "defeat") else 0.29)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--signatures-only", action="store_true")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if not args.signatures_only:
        render_music()
    render_cues(args.signatures_only)
