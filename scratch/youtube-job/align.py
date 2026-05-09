"""Align extracted frames to SRT caption cues."""
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
SRT = HERE / "input" / "video.en.srt"
SCENES = HERE / "output" / "scenes.txt"
FRAMES_DIR = HERE / "frames"
OUT_JSON = HERE / "output" / "transcript.json"
OUT_MD = HERE / "output" / "aligned.md"

TS_RE = re.compile(
    r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*"
    r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})"
)


def srt_to_seconds(h, m, s, ms):
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0


def parse_srt(path):
    cues = []
    block = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines() + [""]:
        if line.strip() == "":
            if block:
                ts_line = next((l for l in block if "-->" in l), None)
                if ts_line:
                    m = TS_RE.search(ts_line)
                    if m:
                        start = srt_to_seconds(*m.groups()[:4])
                        end = srt_to_seconds(*m.groups()[4:])
                        text_lines = block[block.index(ts_line) + 1:]
                        text = " ".join(t.strip() for t in text_lines if t.strip())
                        text = re.sub(r"<[^>]+>", "", text).strip()
                        if text:
                            cues.append({"start": start, "end": end, "text": text})
            block = []
        else:
            block.append(line)
    # YouTube auto-caps repeat content across cues; dedupe consecutive identical text.
    deduped = []
    for c in cues:
        if deduped and deduped[-1]["text"] == c["text"]:
            deduped[-1]["end"] = c["end"]
        else:
            deduped.append(c)
    return deduped


def find_cue_for_time(t, cues):
    for c in cues:
        if c["start"] <= t <= c["end"]:
            return c
    if not cues:
        return None
    # Nearest cue by start time.
    return min(cues, key=lambda c: abs(c["start"] - t))


def fmt_ts(t):
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = t - h * 3600 - m * 60
    return f"{h:02d}:{m:02d}:{s:06.3f}"


def main():
    cues = parse_srt(SRT)
    OUT_JSON.write_text(json.dumps(cues, indent=2))

    scene_times = [float(t) for t in SCENES.read_text().split() if t.strip()]
    frames = sorted(FRAMES_DIR.glob("*.jpg"))

    rows = []
    for frame_path, t in zip(frames, scene_times):
        cue = find_cue_for_time(t, cues)
        rows.append({
            "t": t,
            "frame": frame_path.name,
            "caption": cue["text"] if cue else "",
            "cue_start": cue["start"] if cue else None,
            "cue_end": cue["end"] if cue else None,
        })

    md = ["# Video transcript with aligned frames", ""]
    md.append(f"- Source: `input/video.mp4`")
    md.append(f"- Cues: {len(cues)}  Frames: {len(frames)}")
    md.append("")
    for r in rows:
        md.append(f"## {fmt_ts(r['t'])}  -  `{r['frame']}`")
        md.append("")
        md.append(f"![{r['frame']}](../frames/{r['frame']})")
        md.append("")
        md.append(f"> {r['caption']}" if r["caption"] else "> _(no caption at this time)_")
        md.append("")
    OUT_MD.write_text("\n".join(md))
    print(f"    wrote {OUT_MD} ({len(rows)} aligned frames, {len(cues)} cues)")


if __name__ == "__main__":
    main()
