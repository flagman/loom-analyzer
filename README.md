# loom-screenshots

A [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) that pulls still frames out of a [Loom](https://www.loom.com) video — at specific timecodes, at regular intervals, or at scene changes.

It's a thin wrapper around `yt-dlp` (download) + `ffmpeg` (extract) packaged so Claude Code triggers it automatically when you mention a Loom URL and screenshots, **or** when you're trying to make sense of a Loom transcript that doesn't make sense without seeing the screen.

## Why

Loom recordings are primarily visual — someone points at things on a screen and says "here", "this button", "as you can see". Transcripts of those recordings are often near-useless on their own. This skill lets Claude Code pull the relevant frames so it (and you) can actually see what the speaker is talking about.

## Requirements

macOS with [Homebrew](https://brew.sh).

```bash
brew install yt-dlp ffmpeg
```

That's it. No API keys, no Loom account needed — works for any Loom video that loads in an incognito browser.

## Install

```bash
git clone https://github.com/flagman/loom-screenshots.git ~/.claude/skills/loom-screenshots
chmod +x ~/.claude/skills/loom-screenshots/scripts/loom_screenshots.sh
```

Restart Claude Code (or reload skills) and you'll see `loom-screenshots` in the available skills list.

## Usage

Just talk to Claude Code naturally. It picks the right mode from your phrasing.

**Specific moments**
> "Сделай скриншоты из https://www.loom.com/share/abc123 на 1:23 и 2:45"

**Every N seconds**
> "Pull a frame every 10 seconds from https://www.loom.com/share/abc123"

**Scene changes (good for slide decks / screen-share)**
> "Get the key frames from https://www.loom.com/share/abc123 — only where the screen actually changes"

**Decoding an opaque transcript (the killer use case)**
> "Here's the transcript from https://www.loom.com/share/abc123. They keep saying 'click this' and 'see the error here' but I can't follow what they're showing. Help me make sense of it."

In the last case the skill scans the transcript for deictic references ("this", "here", "вот тут"), extracts frames at those exact timecodes, and Claude reads the PNGs back so it can describe what's actually on screen at each moment — tied to the transcript line that needed it.

## Direct script usage

If you want to run it without Claude:

```bash
SCRIPT=~/.claude/skills/loom-screenshots/scripts/loom_screenshots.sh

# Frames at specific timecodes
"$SCRIPT" "https://www.loom.com/share/<id>" --at "0:23,1:45,3:10" --out ./frames

# One frame every 10 seconds
"$SCRIPT" "https://www.loom.com/share/<id>" --every 10 --out ./frames

# Scene changes (default threshold 0.3; lower = more frames)
"$SCRIPT" "https://www.loom.com/share/<id>" --scenes --out ./frames
"$SCRIPT" "https://www.loom.com/share/<id>" --scenes 0.2 --out ./frames

# Keep the downloaded mp4 too
"$SCRIPT" "https://www.loom.com/share/<id>" --every 30 --keep-video --out ./frames
```

URLs accepted: `loom.com/share/...`, `loom.com/embed/...`, or just the bare video ID.

Timecodes accepted: `HH:MM:SS`, `MM:SS`, or plain seconds — comma-separated for multiple.

## What it can't do

- **Private Loom videos** that require login. The skill uses `yt-dlp` against the public share URL — if Loom asks for auth, it can't get past it. For private videos look at the cookie-based [karbassi/mcp-loom](https://github.com/karbassi/loom-mcp) MCP server instead.
- **Audio extraction / video editing** — out of scope. This is a screenshot tool.

## How it works

1. `yt-dlp -f http-transcoded` downloads the video (transcoded MP4 preferred, falls back to whatever's available) into a temp directory.
2. `ffmpeg` extracts the frames using one of three filters depending on mode:
   - `--at` → input-seek (`-ss` before `-i`) for fast accurate per-timestamp extraction
   - `--every N` → `-vf fps=1/N`
   - `--scenes T` → `-vf "select=gt(scene\,T)" -vsync vfr`
3. The temp video is deleted unless you pass `--keep-video`.

## License

MIT — see [LICENSE](LICENSE).
