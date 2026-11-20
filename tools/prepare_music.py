"""Convert the two credited Incompetech downloads into the distributed game tracks."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


OUTPUT = Path(__file__).resolve().parents[1] / "assets/audio"
TRACKS = {
    "Evening": ("45e91c3a804bab0a27f54323a34b3a404cfb172ccace169518384afdb51c311a", -19.0),
    "Angevin": ("425f5febc62aee69761f16eae09158c35fd922a72c0fe8165af51c3a1f8818bf", -20.0),
}


def convert(folder, title, digest, target):
    source = folder / (title + ".mp3")
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise ValueError(f"Expected the credited {title} recording from incompetech.com")
    analysis = subprocess.run(["ffmpeg", "-hide_banner", "-i", source, "-vn", "-af",
                               "loudnorm=print_format=json", "-f", "null", "-"],
                              capture_output=True, text=True, errors="replace", check=True).stderr
    levels = json.loads(analysis[analysis.rindex("{"):analysis.rindex("}")+1])
    gain = min(target-float(levels["input_i"]), -2.0-float(levels["input_tp"]))
    duration = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                              "-of", "csv=p=0", source], text=True))
    filters = f"volume={gain:.2f}dB,afade=t=in:d=0.10,afade=t=out:st={duration-0.35:.3f}:d=0.35"
    output = OUTPUT / (title.lower() + ".ogg")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", source, "-map", "0:a:0",
                    "-map_metadata", "-1", "-af", filters, "-ar", "44100", "-ac", "2", "-c:a", "libvorbis",
                    "-q:a", "5", "-metadata", "title=" + title, "-metadata", "artist=Kevin MacLeod",
                    "-metadata", "license=https://creativecommons.org/licenses/by/4.0/", output], check=True)
    print(f"{title}: {duration:.2f}s, source {levels['input_i']} LUFS, applied {gain:+.2f} dB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("downloads", type=Path, help="Directory containing Evening.mp3 and Angevin.mp3 from the composer")
    args = parser.parse_args()
    for name, (sha, loudness) in TRACKS.items():
        convert(args.downloads, name, sha, loudness)
