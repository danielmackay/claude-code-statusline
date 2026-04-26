# Claude Code Statusline

A custom statusline script for [Claude Code](https://claude.ai/claude-code) that displays real-time session information in your terminal.

Based on [danielmackay/claude-code-statusline](https://github.com/danielmackay/claude-code-statusline) with the following enhancements:

- **Single `jq` call** instead of 10+ — faster rendering on every API response
- **One-line output** — compatible with Claude Code's single-line status bar
- **POSIX `sh`** — runs on macOS, Linux, and any shell (no bash-only features)
- **Thinking mode & effort level** indicators
- **Context window bar** with color-coded thresholds
- **Both rate limits** (5h + 7d) with reset timestamps
- **Session duration** tracker
- **Active agent** display
- **Session name & output style** indicators

![Statusline preview](screenshot.png)

## What It Shows

```
🤖 Opus 4.6 T | 🧠 ██████░░ 75% | 💰 $0.42 | ⏱️ 5h ████░░░░ 45% ↻2:30PM | 📁 my-project | 🌿 develop +3 ~5 | 🕐 01:23:45
```

| Segment | Description |
|---|---|
| 🤖 Model | Active model + thinking mode (`T`) + effort level |
| 🧠 Context | Context window remaining with color bar (green >50%, yellow 20-50%, red <20%) |
| 💰 Cost | Cumulative session cost in USD |
| ⏱️ Rate Limit | 5h/7d usage bars with percentage and reset time |
| 📁 Folder | Git repo root name (or current directory) |
| 🌿 Branch | Current branch + staged (`+N` green) and modified (`~N` yellow) file counts |
| 🌳 Worktree | Active git worktree name (if any) |
| 🕐 Duration | Session elapsed time (HH:MM:SS) |
| ⚡ Agent | Active subagent name (if running) |
| `[name]` | Session name (if set) |

Segments only appear when they have data — no empty placeholders.

## Prerequisites

- [Claude Code](https://claude.ai/claude-code) CLI installed
- [`jq`](https://jqlang.github.io/jq/) for JSON parsing
- `git` for branch and diff stats

```sh
# macOS
brew install jq

# Ubuntu/Debian
apt-get install jq
```

## Setup

**1. Copy the script:**

```sh
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

**2. Add to `~/.claude/settings.json`** (global) or `.claude/settings.json` (per-project):

```json
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/statusline-command.sh"
  }
}
```

**3. Start Claude Code** — the statusline appears automatically.

## Customization

### Color Thresholds

Context window and rate limits use the same color scheme:

| Color | Condition |
|---|---|
| 🟢 Green | < 70% used |
| 🟡 Yellow | 70–89% used |
| 🔴 Red | ≥ 90% used |

### Available JSON Fields

The script receives a JSON object on stdin from Claude Code:

| Field | Description |
|---|---|
| `model.display_name` | Active model name |
| `context_window.used_percentage` | Context usage (float) |
| `context_window.remaining_percentage` | Context remaining (float) |
| `cost.total_cost_usd` | Session cost |
| `workspace.current_dir` | Current working directory |
| `worktree.name` | Active worktree name |
| `session_id` | Unique session identifier |
| `session_name` | User-set session name |
| `agent.name` | Active subagent name |
| `effort_level` | Current effort setting |
| `output_style.name` | Current output style |
| `rate_limits.five_hour.used_percentage` | 5h rate limit usage |
| `rate_limits.five_hour.resets_at` | 5h reset Unix timestamp |
| `rate_limits.seven_day.used_percentage` | 7d rate limit usage |
| `rate_limits.seven_day.resets_at` | 7d reset Unix timestamp |

### Performance

The script uses a single `jq` invocation with `eval` to parse all fields at once, avoiding the overhead of spawning multiple subprocesses per render cycle.

## Credits

Original script by [@danielmackay](https://github.com/danielmackay). Enhanced with single-parse optimization, one-line layout, thinking/effort/agent indicators, session tracking, and context bar visualization.
