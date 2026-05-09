# YouTube transcribe + frame alignment

Pipeline for transcribing YouTube videos and pairing transcript cues with
representative frames. Supports multiple videos in one run.

## Why this lives outside the runtime
The sandbox blocks egress to `youtube.com`, `googlevideo.com`, Google Drive,
Hugging Face, OpenAI's model CDN, and basically every third-party file host.
So we can't download videos or auto-fetch a Whisper model from in here.

## Workflow

1. **On your machine**, download video + auto-captions. Repeat for each video,
   substituting the video id:
   ```bash
   yt-dlp \
     -f "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]" \
     --write-auto-sub --sub-lang en --convert-subs srt \
     -o "video.%(ext)s" \
     https://youtu.be/<VIDEO_ID>
   ```

2. **Drop the outputs into `input/<VIDEO_ID>/`:**
   - `input/<VIDEO_ID>/video.mp4`
   - `input/<VIDEO_ID>/video.en.srt`

   Currently expected:
   - `input/bCljOfCH8Ms/`
   - `input/w0S-khYCaB4/`

3. **Run the pipeline (in this sandbox):**
   ```bash
   bash run.sh                 # process all videos in input/
   bash run.sh bCljOfCH8Ms     # process just one
   ```

## Outputs (per video)
- `frames/<id>/scene_NNN_tSSSS.SS.jpg` - one frame per scene change
- `output/<id>/transcript.json` - parsed SRT cues
- `output/<id>/scenes.txt` - scene-change timestamps
- `output/<id>/aligned.md` - readable report: timestamp + caption + frame

## Tuning
- `SCENE_THRESHOLD=0.20 bash run.sh` -> more frames (default 0.30)
