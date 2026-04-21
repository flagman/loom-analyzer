---
name: loom-screenshots
description: Extract still frames (screenshots) from a Loom video. Use whenever the user provides a Loom URL (loom.com/share/... or loom.com/embed/...) and asks for screenshots, frames, stills, thumbnails, or wants to capture moments — at specific timecodes, at regular intervals, or at scene changes. ALSO trigger proactively when working with a Loom video transcript that is hard to follow without visuals — e.g. the transcript contains deictic references ("look here", "this button", "as you can see", "вот тут", "эта кнопка", "вот это окно", "смотрите сюда"), references UI elements / what's on screen without describing them, or the user says they don't understand what's being shown / discussed in the video. In those cases pull frames at the timecodes where the ambiguity occurs (or at scene changes if no timecodes are present) so the user can actually see what the speaker is pointing at. Also trigger on Russian phrases like "скриншот из loom", "кадры из loom", "сделай скрин из лум видео", "вытащи кадр из loom", "не понятно что показывают", "что там за кнопка", "посмотри что в видео".
allowed-tools: Bash(*/loom_screenshots.sh*), Bash(yt-dlp*), Bash(ffmpeg*), Bash(open*), Bash(ls*), Bash(mkdir*), Read
---

# Loom Screenshots

Extracts still frames from a Loom video by combining `yt-dlp` (download) + `ffmpeg` (frame extraction). Wrapped in `scripts/loom_screenshots.sh`.

## Pick a mode

The user will want one of these. If their request is ambiguous, ask — don't guess.

| Want | Mode | Example phrase |
|---|---|---|
| Frames at known moments | `--at` | "скрин на 1:23 и 2:45", "frame at 0:30" |
| A frame every N seconds | `--every` | "кадр каждые 10 секунд", "thumbnail grid" |
| Only when the screen changes | `--scenes` | "ключевые кадры", "scene changes", "where slides change" |
| Decode an opaque transcript | `--at` (derived) | see below |

A single screenshot is just `--at` with one timecode.

## Decoding an opaque transcript

If you've been handed a Loom URL plus a transcript and the transcript is hard to follow without visuals (a Loom recording is *primarily* visual — a person points at things on a screen), don't make the user beg for screenshots. Offer them, or just pull them, depending on how stuck the user sounds.

**Signals that the transcript needs visual backup:**

- **Deictic references with no antecedent** — "click here", "this button", "that field", "вот тут", "эта штука", "вот это окно", "смотрите сюда". The speaker is pointing at the screen; the words alone don't say *what*.
- **UI / state references without description** — "the error", "the dropdown", "the highlighted row", "красный текст".
- **"As you can see" / "as I'm doing now"** — explicit appeals to vision.
- **The user explicitly says** they don't follow what's happening, asks "что они показывают?", or says the transcript is confusing.

**How to act:**

1. Find the timecodes in the transcript where the dieictic references occur. Most Loom transcripts have `[MM:SS]` or `MM:SS` markers per segment.
2. Pass those timecodes to `--at` (you can pass many at once, comma-separated). Add a small offset (e.g. +1 second) if the speaker says "here" — by the time they say it, the screen is usually already showing the thing.
3. If the transcript has no timecodes, fall back to `--scenes` to grab the screen states; then map them back to the transcript flow.
4. After extraction, walk through the frames with the user inline — `Read` each PNG so Claude Code can see and describe it, then connect each frame to the transcript line it explains.

**Example flow (you don't need user permission for the screenshot step — it's the obvious next move):**

> User: "Вот транскрипт из лум-видео https://www.loom.com/share/abc123 — не пойму, что они там показывают на 1:14 и 2:30, говорят 'вот тут ошибка, видишь?' но я не вижу"

Run:

```bash
"$SCRIPT" "https://www.loom.com/share/abc123" --at "1:15,2:31" --out ./frames
```

Then `Read` both PNGs and explain to the user what's actually on the screen at each moment, tying it back to the transcript lines.

## Running the script

The script lives at `scripts/loom_screenshots.sh` (relative to this skill). Resolve its absolute path before running — for this user it's `/Users/pavel/.claude/skills/loom-screenshots/scripts/loom_screenshots.sh`.

```bash
SCRIPT=/Users/pavel/.claude/skills/loom-screenshots/scripts/loom_screenshots.sh
chmod +x "$SCRIPT"  # first run only

# Specific moments
"$SCRIPT" "https://www.loom.com/share/<id>" --at "0:23,1:45,3:10" --out ./frames

# Every 10 seconds
"$SCRIPT" "https://www.loom.com/share/<id>" --every 10 --out ./frames

# Scene changes (default threshold 0.3; lower = more frames)
"$SCRIPT" "https://www.loom.com/share/<id>" --scenes --out ./frames
"$SCRIPT" "https://www.loom.com/share/<id>" --scenes 0.2 --out ./frames
```

The script accepts share URLs, embed URLs, or a bare video ID. Timecodes can be `HH:MM:SS`, `MM:SS`, or plain seconds — pass them comma-separated to `--at`.

Default output directory is `./loom-frames` in the current working directory. Use `--out` to put frames somewhere specific (the project's `assets/`, the user's `~/Desktop`, etc.).

## After running

Show the user the produced file paths. On macOS you can open the folder for them:

```bash
open ./frames
```

If they want a specific frame inline in the conversation, use the `Read` tool on the PNG — Claude Code renders images visually.

## Why this design

- **One script, three modes** — covers ~all real screenshot needs without bloating the interface.
- **Temp-file download** — the mp4 is fetched once, reused for all frames, then deleted. Use `--keep-video` if the user also wants the video file.
- **Input seek (`-ss` before `-i`)** — fast for `--at` mode; accuracy is well within a frame, which is fine for screenshots. Don't switch to output seek unless the user complains about a specific timestamp being off.
- **Scene threshold 0.3** — sane default for slide-style Loom recordings (talking head + screen share). Drop to 0.2 for subtle changes; raise to 0.5 if too noisy.
- **No auth handling** — works for any video that loads in an incognito browser. Private videos that require Loom login are out of scope; tell the user.

## Failure modes

- **`yt-dlp` 403 or "private video"** — the video requires Loom auth. Not solvable here; suggest using the [karbassi/mcp-loom](https://github.com/karbassi/loom-mcp) MCP server (cookie-based) or downloading the mp4 manually first and pointing ffmpeg at it.
- **No audio stream warnings during download** — harmless for screenshots, ignore.
- **WebM downloaded instead of MP4** — ffmpeg reads both; works fine. If the user specifically needs mp4 alongside the screenshots, the script already requests `http-transcoded` first.
- **Empty output for `--scenes`** — threshold too high. Re-run with `--scenes 0.15`.

## When NOT to use this skill

- The user has a local mp4 already (no Loom URL involved) → just run ffmpeg directly, no need to involve yt-dlp.
- The user wants the *video* downloaded, not screenshots → use `yt-dlp` directly.
- The user wants the *transcript* of a Loom video → suggest the karbassi/mcp-loom MCP server.
