"""Encode a native field or weather reel with the game's action cues."""
import argparse
from array import array
import json
import math
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
    recorded = data["cues"] if "cues" in data else [{"sound": s["sound"], "frame": s["sound_frame"]} for s in data["shots"]]
    effects_gain = (data.get("effects_percent",100)/100)**1.55
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
            audio[start+i] = min(32767, max(-32768, audio[start+i]+round(sample*effects_gain)))
    music = data.get("music", [])
    crossfade = 1.45
    for index, section in enumerate(music):
        start = round(section["frame"] / fps * rate)
        change = round(music[index+1]["frame"] / fps * rate) if index+1 < len(music) else frames*rate/fps
        count = min(len(audio)//channels-start, math.ceil(change+crossfade*rate-start))
        raw = subprocess.check_output(["ffmpeg","-v","error","-i",cues / Path(section["file"]).name,"-t",str(count/rate),
                                       "-f","s16le","-ar",str(rate),"-ac",str(channels),"-"])
        samples = array("h")
        samples.frombytes(raw)
        if sys.byteorder != "little": samples.byteswap()
        for i in range(min(count,len(samples)//channels)):
            fade_in = min(1,i/(crossfade*rate))
            fade_out = min(1,max(0,1-(start+i-change)/(crossfade*rate)))
            gain = (data["music_percent"]/100)**1.55 * (1-math.cos(math.pi*fade_in))/2 * (1-math.cos(math.pi*fade_out))/2
            for channel in range(channels):
                at = (start+i)*channels+channel
                audio[at] = min(32767,max(-32768,audio[at]+round(samples[i*channels+channel]*gain)))
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
            "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart",
            *(["-metadata", "comment=Evening and Angevin by Kevin MacLeod (incompetech.com), CC BY 4.0 https://creativecommons.org/licenses/by/4.0/ - excerpts and mix for gameplay preview."] if music else []), str(output),
        ], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    encode(args.frames, args.output)
