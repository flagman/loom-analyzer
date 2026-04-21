# loom-analyzer

A [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) that lets Claude **read a Loom video**: pull the transcript, decide which moments matter for the task at hand, then extract still frames as visual proof.

It's a thin wrapper around `yt-dlp` (transcript via Loom's GraphQL + video download) and `ffmpeg` (frame extraction), packaged so Claude Code triggers it automatically when a Loom URL shows up — whether you ask for screenshots explicitly or are just trying to make sense of a recording referenced in a Jira ticket / spec / MR.

## Why

Loom recordings are primarily visual. Someone points at things on a screen and says "here", "this button", "as you can see". The transcript alone is full of dangling references; a wall of 30 random scene-change frames is just as bad. The interesting middle is **transcript-first**: read what's said, pick the 3–5 moments that actually answer the question, then pull only those frames. That's what this skill does.

## Requirements

macOS with [Homebrew](https://brew.sh).

```bash
brew install yt-dlp ffmpeg
```

That's it. No API keys, no Loom account needed — works for any Loom video that loads in an incognito browser.

## Install

```bash
git clone https://github.com/flagman/loom-analyzer.git ~/.claude/skills/loom-analyzer
chmod +x ~/.claude/skills/loom-analyzer/scripts/loom_analyzer.sh
```

Restart Claude Code (or reload skills) and you'll see `loom-analyzer` in the available skills list.

## Usage with Claude Code

Just talk naturally — the skill triggers itself.

**Make sense of a video referenced in a ticket** (the killer use case)
> "Дополни тикет STARTUP-4736 деталями из лум-видео в описании"

Claude pulls the VTT, finds the moments where the speaker points at specific UI ("вот видишь Book Online"), extracts only those frames, reads them, and writes a synthesis tying transcript line ↔ screenshot ↔ ticket AC.

**Specific moments**
> "Сделай скриншоты из https://www.loom.com/share/abc123 на 1:23 и 2:45"

**Every N seconds**
> "Pull a frame every 10 seconds from https://www.loom.com/share/abc123"

**Scene changes (good for slide decks / screen-share)**
> "Get the key frames from https://www.loom.com/share/abc123 — only where the screen actually changes"

**Just the transcript, no frames**
> "What does this Loom say? https://www.loom.com/share/abc123"

## Direct script usage

If you want to run it without Claude:

```bash
SCRIPT=~/.claude/skills/loom-analyzer/scripts/loom_analyzer.sh

# Transcript only (fast, no video download)
"$SCRIPT" "https://www.loom.com/share/<id>" --transcript-only --out ./loom-work
# → ./loom-work/<video_id>.en.vtt

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

Subtitle language defaults to whatever Loom's auto-CC produced for the video (usually matches the spoken language). Override with `--lang ru` etc. if a video has multiple subtitle tracks.

## What it can't do

- **Private Loom videos** that require login. The skill uses `yt-dlp` against the public share URL — if Loom asks for auth, it can't get past it. For private videos look at the cookie-based [karbassi/mcp-loom](https://github.com/karbassi/loom-mcp) MCP server instead.
- **Audio extraction / video editing** — out of scope.

## How it works

1. **Transcript phase** (`--transcript-only`): `yt-dlp --skip-download --write-subs --sub-format vtt` hits Loom's GraphQL via yt-dlp's Loom extractor and saves a `.vtt` file. No video downloaded.
2. **Frame phase** (`--at` / `--every` / `--scenes`): `yt-dlp -f http-transcoded` downloads the video into a temp directory, then `ffmpeg` extracts frames using the appropriate filter:
   - `--at` → input-seek (`-ss` before `-i`) for fast accurate per-timestamp extraction
   - `--every N` → `-vf fps=1/N`
   - `--scenes T` → `-vf "select=gt(scene\,T)" -vsync vfr`
3. The temp video is deleted unless you pass `--keep-video`.

When Claude orchestrates the two phases together (the typical case), it runs phase 1, reads the VTT, decides which timecodes matter for the user's actual question, then runs phase 2 with `--at <chosen times>`. Sharing the same `--out` directory keeps everything in one place.

## License

MIT — see [LICENSE](LICENSE).
