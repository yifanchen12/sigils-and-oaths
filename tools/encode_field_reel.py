"""Encode the native --field-frames capture with the game's exact action cues."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import wave


def encode(directory: Path, output: Path) -> None:
    data = json.loads((directory / "shots.json").read_text(encoding="utf-8"))
    fps, frames = data["fps"], data["frames"]
    cues = Path(__file__).resolve().parents[1] / "assets" / "audio"
    rate, channels, width = 32000, 2, 2
    audio = bytearray(round(frames / fps * rate) * channels * width)
    for shot in data["shots"]:
        file = cues / Path(shot["sound"]).name
        with wave.open(str(file), "rb") as cue:
            if (cue.getframerate(), cue.getnchannels(), cue.getsampwidth()) != (rate, channels, width):
                raise ValueError(f"Unexpected sample format in {file.name}")
            samples = cue.readframes(cue.getnframes())
        start = round(shot["sound_frame"] / fps * rate) * channels * width
        end = min(start + len(samples), len(audio))
        audio[start:end] = samples[:end-start]
    with tempfile.TemporaryDirectory() as scratch:
        soundtrack = Path(scratch) / "action-cues.wav"
        with wave.open(str(soundtrack), "wb") as track:
            track.setparams((channels, width, rate, 0, "NONE", "not compressed"))
            track.writeframes(audio)
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-y", "-framerate", str(fps), "-i", str(directory / "cast-%04d.png"),
            "-i", str(soundtrack), "-frames:v", str(frames), "-vf", "crop=1280:720:320:184",
            "-c:v", "libx264", "-crf", "17", "-preset", "medium", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(output),
        ], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    encode(args.frames, args.output)
