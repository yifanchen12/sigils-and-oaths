"""Encode a native field or weather reel with the game's action cues."""
import argparse
from array import array
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import wave


def encode(directory: Path, output: Path) -> None:
    data = json.loads((directory / "shots.json").read_text(encoding="utf-8"))
    fps, frames = data["fps"], data["frames"]
    cues = Path(__file__).resolve().parents[1] / "assets" / "audio"
    rate, channels, width = 32000, 2, 2
    audio = array("h", [0]) * (round(frames / fps * rate) * channels)
    recorded = data.get("cues", [{"sound": s["sound"], "frame": s["sound_frame"]} for s in data["shots"]])
    for onset in recorded:
        file = cues / Path(onset["sound"]).name
        with wave.open(str(file), "rb") as cue:
            if (cue.getframerate(), cue.getnchannels(), cue.getsampwidth()) != (rate, channels, width):
                raise ValueError(f"Unexpected sample format in {file.name}")
            samples = array("h")
            samples.frombytes(cue.readframes(cue.getnframes()))
        if sys.byteorder != "little":
            samples.byteswap()
        start = round(onset["frame"] / fps * rate) * channels
        for i, sample in enumerate(samples[:max(0, len(audio)-start)]):
            audio[start+i] = min(32767, max(-32768, audio[start+i]+sample))
    if sys.byteorder != "little":
        audio.byteswap()
    with tempfile.TemporaryDirectory() as scratch:
        soundtrack = Path(scratch) / "action-cues.wav"
        with wave.open(str(soundtrack), "wb") as track:
            track.setparams((channels, width, rate, 0, "NONE", "not compressed"))
            track.writeframes(audio)
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-y", "-framerate", str(fps), "-i", str(directory / "cast-%04d.png"),
            "-i", str(soundtrack), "-frames:v", str(frames), "-vf",
            "scale=1600:900" if data.get("full_board") else "crop=1280:720:320:184",
            "-c:v", "libx264", "-crf", "17", "-preset", "medium", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(output),
        ], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    encode(args.frames, args.output)
