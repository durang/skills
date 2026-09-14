---
name: "local-media-fallbacks"
description: "Voice note not analyzed, audio reply requested, or the pdf tool auth-fails: transcribe, speak, and extract using local CLI tools on the host."
---

# Local Media Fallbacks

Hosted media tooling fails on this host in three recurring ways. Try the built-in tool first; when it errors, use the local path below.

## Inbound voice notes that fail analysis

Voice notes sometimes reach you as `[Audio attachment could not be analyzed]`. The file is still staged on disk — you can read it yourself.

1. Locate the payload: `ls /home/ec2-user/media/inbound/openclaw-staged-*/`. The audio is `input-<uuid>.ogg`. Continue once you have a concrete path.

2. Convert to the sample rate Whisper expects, and measure the clip so you can size the wait:

   ```
   ffmpeg -y -i "<path>.ogg" -ar 16000 -ac 1 /tmp/voice.wav
   ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 /tmp/voice.wav
   ```

3. Transcribe with the `small` model, in the background:

   ```
   nohup whisper /tmp/voice.wav --model small --language Spanish \
     --task transcribe --output_format txt --output_dir /tmp/w --fp16 False \
     > /tmp/w.log 2>&1 &
   ```

   Use `small`, not `base`. On Spanish speech `base` garbles proper nouns and clause boundaries badly enough to change what the user asked; `small` returns usable text. Match `--language` to the speaker. First use of a model downloads weights (~461 MB for `small`), which happens before any transcription output appears.

4. Poll for the transcript file rather than blocking on it:

   ```
   [ -s /tmp/w/voice.txt ] && cat /tmp/w/voice.txt
   ```

   This host has 2 vCPUs; a two-minute clip takes several minutes and inline waits exceed the tool timeout. Loop with `sleep`, or re-check on a later turn. The transcript lands at `<output_dir>/<wav-basename>.txt`.

5. Tell the user you transcribed locally and restate the questions you extracted. Whisper output still contains errors on names and numbers, so surfacing your reading lets them correct you before you act on it.

## Outbound audio replies

When the user asks to be answered in audio, `tts` is the delivery path.

- **Retry on failure before anything else.** A `tts` error listing every provider as failed is usually the primary provider timing out, not a dead chain. Re-issue the identical call — the retry succeeds. Only report a real outage after the retry also fails.

- **Never substitute text for a requested audio.** Sending the spoken text as a chat message when audio was asked for counts as undelivered, not as partial delivery.

- **Send multi-part audio one call at a time, in order.** Issue the next call only after the previous one returns, so parts arrive in sequence.

- **Write for the ear.** No markdown, no symbols, numbers spelled out as words. Symbols and asterisks are read aloud literally and ruin the take.

## PDFs when the `pdf` tool fails

The `pdf` tool routes through hosted vision models and fails outright when provider auth is missing or exhausted. Extract locally instead:

```
pdftotext -layout <file>.pdf /tmp/out.txt
```

Then read `/tmp/out.txt`. `-layout` preserves headings and block structure well enough to pull a named section (a transcript, a summary) out of a long generated document.
