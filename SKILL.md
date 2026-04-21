---
name: loom-analyzer
description: Read Loom videos — pull the transcript, pick the moments that matter for the task at hand, and extract still frames as visual proof. Use whenever the user provides a Loom URL (loom.com/share/... or loom.com/embed/...) for ANY of these reasons — (a) explicit screenshot ask ("сделай скрин на 1:23", "frames every 10 seconds"), (b) wants to understand or summarize what's in the video ("разбери видео", "что там показывают", "пройдись по лум и достань детали", "дополни тикет по этому видео"), (c) is working with a Loom URL inside a Jira ticket / GitLab MR / spec where the recording is the source of truth, (d) is reading a transcript that's hard to follow without visuals — deictic references ("look here", "this button", "вот тут", "эта кнопка", "смотрите сюда"), UI elements mentioned but not described, or the user says they don't follow what's being shown. The skill's primary mode is transcript-first: download the VTT (fast, no video), let the model pick timecodes by the user's actual question, then extract only those frames. Falls back to scene-change extraction if the video has no captions. Also trigger on Russian phrases like "скриншот из loom", "кадры из loom", "вытащи кадр из лум", "не понятно что показывают", "что там за кнопка", "посмотри что в видео", "перескажи лум", "выжимка из видео".
allowed-tools: Bash(*/loom_analyzer.sh*), Bash(yt-dlp*), Bash(ffmpeg*), Bash(open*), Bash(ls*), Bash(mkdir*), Read
---

# Loom Analyzer

Reads a Loom video the way a person would: pull the transcript, decide which moments matter for the task at hand, then extract still frames as proof. Wraps `yt-dlp` (transcript via Loom GraphQL + video download) and `ffmpeg` (frame extraction). The script is `scripts/loom_analyzer.sh`.

## Pick a mode

The user will want one of these. If their request is ambiguous, ask — don't guess.

| Want | Mode | Example phrase |
|---|---|---|
| Frames at known moments | `--at` | "скрин на 1:23 и 2:45", "frame at 0:30" |
| A frame every N seconds | `--every` | "кадр каждые 10 секунд", "thumbnail grid" |
| Only when the screen changes | `--scenes` | "ключевые кадры", "scene changes", "where slides change" |
| Just the transcript (no video) | `--transcript-only` | "что говорят в видео", "перескажи лум", "выжимка" |
| Decode an opaque video / link | **transcript-first** workflow (see below) | "что в этом видео", "разбери видео по тикету", you have a Loom URL but no clear ask |

A single screenshot is just `--at` with one timecode.

**Default to transcript-first** when the user gives you a Loom URL with vague intent ("разбери", "что там", "пройдись по видео и достань детали", "дополни тикет"), or when you need to make sense of *what's* on screen. Blind `--scenes` produces dozens of frames you then have to manually triage; the transcript tells you exactly which moments matter for the question at hand.

## Transcript-first workflow (the main loop)

The most useful thing this skill does isn't "give me 30 random frames" — it's "tell me *what's actually being shown and discussed*, with proof". The flow is two phases:

### Phase 1 — read what's said

Pull the VTT transcript first. It's fast (no video download, just GraphQL via yt-dlp), and gives you timestamped segments:

```bash
"$SCRIPT" "$URL" --transcript-only --out ./loom-work
# → ./loom-work/<video_id>.en.vtt
```

For Russian-language recordings the VTT will already be in Russian — no `--lang` needed (Loom's auto-CC matches the spoken language). Override with `--lang ru` etc. if a video has multiple subtitle tracks.

`Read` the VTT. Each segment looks like:

```
3
00:00:23.190 --> 00:00:28.004
Точек, точек, точек. Вот видишь бук онлайн, вот он их этот,

4
00:00:28.004 --> 00:00:31.444
экшн-батюн, смотри,
```

### Phase 2 — pick moments that answer the question

Now use your understanding of the user's task to choose *which* timecodes matter. Don't pull frames for every line — that defeats the point. You're looking for:

- **Deictic anchors** — "вот тут", "this button", "as you can see", "look here". The speaker is pointing at something; the frame at that moment is the antecedent.
- **Topic-relevant claims** — if the user is asking about Acceptance Criteria, find lines where the speaker describes a behavior or shows a counter-example. If they want a bug repro, find the moment of failure.
- **Transitions** — moments right after the speaker says "let's look at the next one" / "теперь" / "следующий пример" — likely a new screen worth capturing.

Add a small offset (~1s) to the segment's *end* timestamp when the speaker says "here" / "вот это" — by the time the word is uttered, the screen is usually already showing the thing.

Then pull only those frames:

```bash
"$SCRIPT" "$URL" --at "0:30,1:14,2:31" --out ./loom-work/frames
```

### Phase 3 — synthesize

`Read` each PNG so you can actually see what's on screen, then write the user a synthesis tying transcript line ↔ frame ↔ task. Don't dump raw transcripts and 12 image paths — distill it.

### When transcript fails

- **No CC available** for the video → the script exits with an error. Fall back to `--scenes` and walk the user through what you see.
- **Transcript exists but doesn't help** (silent demo, music-only, foreign language with bad CC) → also fall back to `--scenes`, but warn the user the transcript was unusable so they know why you're guessing more.

### Signals that visual backup is needed (use as triggers, not as gospel)

- Deictic references with no antecedent in the words: "click here", "this button", "вот тут".
- UI / state references the words don't actually describe: "the error", "the dropdown", "красный текст".
- Explicit appeals to vision: "as you can see", "as I'm doing now", "смотри".
- The user says they don't follow what's happening, asks "что они показывают?", or says the transcript/summary is confusing.

In those cases don't ask permission to pull frames — it's the obvious next move.

## Running the script

The script lives at `scripts/loom_analyzer.sh` (relative to this skill). Resolve its absolute path before running — for this user it's `/Users/pavel/.claude/skills/loom-analyzer/scripts/loom_analyzer.sh`.

```bash
SCRIPT=/Users/pavel/.claude/skills/loom-analyzer/scripts/loom_analyzer.sh
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
