# YouTube transcribe + frame alignment

Pipeline for transcribing a YouTube video and pairing transcript cues with
representative frames.

## Why this lives outside the runtime
The sandbox blocks egress to `youtube.com` / `googlevideo.com` /
`huggingface.co` / OpenAI's model CDN. So we can't download the video or
auto-fetch a Whisper model from in here. Workflow:

1. **On your machine**, download video + auto-captions:
   ```bash
   yt-dlp \
     -f "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]" \
     --write-auto-sub --sub-lang en --convert-subs srt \
     -o "video.%(ext)s" \
     https://youtu.be/bCljOfCH8Ms
   ```

2. **Drop the outputs into `input/`:**
   - `input/video.mp4`
   - `input/video.en.srt`

3. **Run the pipeline (in this sandbox):**
   ```bash
   bash run.sh
   ```

## Outputs
- `frames/scene_NNN_tSSSS.SS.jpg` - one frame per scene change
- `output/transcript.json` - parsed SRT cues
- `output/scenes.txt` - scene-change timestamps
- `output/aligned.md` - readable report: timestamp + caption + frame image

## Tuning
- `SCENE_THRESHOLD=0.20 bash run.sh` -> more frames (default 0.30)
- Replace `input/video.en.srt` with a Whisper-generated SRT if auto-captions
  are missing or low quality.
