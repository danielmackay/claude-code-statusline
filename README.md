# Claude Code Statusline

A custom statusline script for [Claude Code](https://claude.ai/claude-code) that displays real-time session information in your terminal.

![Statusline preview](screenshot.png)

## What It Shows

```
🤖 Claude Sonnet 4.6 | 🧠 12% | 💰 $0.04 | ⏱️ 5h ████░░░░░░ 42% resets 2:00PM
📁 my-project | 🌳 my-feature | 🌿 main +42 -7
```

| Field | Description |
|---|---|
| 🤖 Model | Active Claude model name |
| 🧠 Context | Context window usage percentage |
| 💰 Cost | Cumulative session cost in USD |
| ⏱️ Rate Limit | 5-hour rate limit usage bar, percentage, and reset time |
| 📁 Folder | Current working directory name |
| 🌳 Worktree | Active git worktree name |
| 🌿 Branch | Current git branch with lines added/removed |

## Prerequisites

- [Claude Code](https://claude.ai/claude-code) CLI installed
- [`jq`](https://jqlang.github.io/jq/) — for parsing the JSON input from Claude Code
- `git` — for branch and diff stats

Install `jq` if needed:

```sh
# macOS
brew install jq

# Ubuntu/Debian
apt-get install jq
```

## Setup

**1. Copy the script somewhere accessible:**

```sh
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

**2. Add the statusline configuration to `.claude/settings.json`:**

For a **global** setup (applies to all projects), edit `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/statusline-command.sh",
    "padding": 0
  }
}
```

For a **project-level** setup, add the same block to `.claude/settings.json` in your project root.

**3. Start Claude Code** — the statusline will appear automatically.

### Subagent rows (optional)

`subagent-statusline.sh` replaces each row of the agent panel below the prompt:

```
builder · 🤖 Opus 5.5 · Capturing History lb volume screenshot                 🧠 15% · 6m 35s
```

- The row starts with the agent type (`builder`, `general-purpose`), then the model (`claude-opus-5-5` shows as `Opus 5.5`) and effort when Claude Code sends one.
- The text is the agent's current activity (`label`), truncated to fit the row width.
- Context % (the token count divided by the model's context window) and the elapsed time sit at the right edge. The clock shows only while the agent is running.
- On a narrow terminal the activity shortens first, then the model drops.

Add it next to `statusLine`:

```json
{
  "subagentStatusLine": {
    "type": "command",
    "command": "sh ~/.claude/subagent-statusline.sh"
  }
}
```

## Customization

The script reads a JSON object from stdin with the following fields:

| Field | Description |
|---|---|
| `model.display_name` | Name of the active model |
| `context_window.used_percentage` | Context usage as a float |
| `worktree.name` | Active worktree name |
| `cost.total_cost_usd` | Session cost |
| `cost.total_lines_added` | Lines added this session |
| `cost.total_lines_removed` | Lines removed this session |
| `workspace.current_dir` | Current working directory |
| `rate_limits.five_hour.used_percentage` | 5-hour rate limit usage percentage |
| `rate_limits.five_hour.resets_at` | Unix timestamp when 5-hour limit resets |
| `rate_limits.seven_day.used_percentage` | 7-day rate limit usage percentage (available for optional display) |
| `rate_limits.seven_day.resets_at` | Unix timestamp when 7-day limit resets (available for optional display) |

The rate-limit bar uses color thresholds: green (<70%), yellow (70-89%), red (>=90%).

By default, the script shows the 5-hour limit and keeps 7-day output commented out. You can enable 7-day display by uncommenting the `rate_limit_str` line near the bottom of `statusline-command.sh`.

Edit `statusline-command.sh` to change the format, add new fields, or adjust colors.
