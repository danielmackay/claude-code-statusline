#!/bin/sh
# Claude Code Status Line
# Single jq call, POSIX sh, one-line output
# Segments: model+thinking+effort, context bar, cost, rate limits w/ reset,
#           directory, git branch+staged/modified, session duration, agent, session name

input=$(cat)

# --- Single jq parse for all fields ---
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "?")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "remaining=\(.context_window.remaining_percentage // "")",
  @sh "total_cost=\(.cost.total_cost_usd // "")",
  @sh "current_dir=\(.workspace.current_dir // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "session_name=\(.session_name // "")",
  @sh "agent_name=\(.agent.name // "")",
  @sh "effort=\(.effort_level // "")",
  @sh "output_style=\(.output_style.name // "")",
  @sh "worktree=\(.worktree.name // "")",
  @sh "rl_5h_pct=\(.rate_limits.five_hour.used_percentage // "" | tostring | split(".")[0])",
  @sh "rl_5h_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "rl_7d_pct=\(.rate_limits.seven_day.used_percentage // "" | tostring | split(".")[0])",
  @sh "rl_7d_reset=\(.rate_limits.seven_day.resets_at // "")"
')"

[ -z "$effort" ] && [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ] && effort="$CLAUDE_CODE_EFFORT_LEVEL"

# --- Thinking mode detection ---
thinking=""
if [ -f "$HOME/.claude/settings.json" ]; then
  thinking_val=$(jq -r '.alwaysThinkingEnabled // empty' "$HOME/.claude/settings.json" 2>/dev/null)
  [ "$thinking_val" = "true" ] && thinking="T"
fi
[ -z "$thinking" ] && [ -n "$MAX_THINKING_TOKENS" ] && thinking="T"

# --- Session duration ---
session_duration=""
if [ -n "$session_id" ]; then
  session_dir="/tmp/claude-session-times"
  mkdir -p "$session_dir"
  session_file="$session_dir/$session_id"
  [ ! -f "$session_file" ] && date +%s > "$session_file"
  if [ -f "$session_file" ]; then
    elapsed=$(( $(date +%s) - $(cat "$session_file") ))
    session_duration=$(printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)))
  fi
fi

# --- Colors ---
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MAGENTA='\033[35m'
DIM='\033[38;5;245m'
RST='\033[0m'

# --- Helpers ---
make_bar() {
  pct="$1"; width=8
  filled=$(( pct * width / 100 ))
  i=0; bar=""
  while [ $i -lt $filled ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt $width ];  do bar="${bar}░"; i=$(( i + 1 )); done
  printf "%s" "$bar"
}

threshold_color() {
  pct="$1"
  if [ "$pct" -ge 90 ] 2>/dev/null; then printf "%b" "$RED"
  elif [ "$pct" -ge 70 ] 2>/dev/null; then printf "%b" "$YELLOW"
  else printf "%b" "$GREEN"
  fi
}

# --- Build segments ---
parts=""
sep=" ${DIM}|${RST} "
add_part() { [ -n "$parts" ] && parts="${parts}${sep}"; parts="${parts}$1"; }

# 🤖 Model + thinking + effort
model_str="$model"
[ -n "$thinking" ] && model_str="${model_str} ${MAGENTA}${thinking}${RST}"
[ -n "$effort" ] && [ "$effort" != "default" ] && model_str="${model_str} ${DIM}${effort}${RST}"
add_part "$(printf '🤖 %s' "$model_str")"

# 🧠 Context usage with bar
if [ -n "$remaining" ]; then
  pct=$(printf '%.0f' "$remaining")
  color=$(threshold_color $((100 - pct)))
  bar=$(make_bar "$pct")
  add_part "$(printf '🧠 %b%s %s%%%b' "$color" "$bar" "$pct" "$RST")"
elif [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  color=$(threshold_color "$pct")
  bar=$(make_bar $((100 - pct)))
  add_part "$(printf '🧠 %b%s %s%%%b' "$color" "$bar" "$pct" "$RST")"
fi

# 💰 Cost
if [ -n "$total_cost" ]; then
  cost_display=$(awk "BEGIN { printf \"%.2f\", $total_cost }")
  add_part "$(printf '💰 $%s' "$cost_display")"
fi

# ⏱️ Rate limits with reset time
format_rl() {
  pct="$1"; reset_ts="$2"; label="$3"
  [ -z "$pct" ] && return 1
  color=$(threshold_color "$pct")
  bar=$(make_bar "$pct")
  reset_time=""
  if [ -n "$reset_ts" ]; then
    reset_time=$(date -r "$reset_ts" "+%-I:%M%p" 2>/dev/null || date -d "@$reset_ts" "+%-I:%M%p" 2>/dev/null)
    [ -n "$reset_time" ] && reset_time=" ↻${reset_time}"
  fi
  printf "%b%s %s %s%%%s%b" "$color" "$label" "$bar" "$pct" "$reset_time" "$RST"
}

rl_str=""
rl_5h=$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h")
[ -n "$rl_5h" ] && rl_str="$rl_5h"
rl_7d=$(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d")
[ -n "$rl_7d" ] && { [ -n "$rl_str" ] && rl_str="${rl_str} ${DIM}·${RST} ${rl_7d}" || rl_str="$rl_7d"; }
[ -n "$rl_str" ] && add_part "$(printf '⏱️  %s' "$rl_str")"

# 📁 Directory
if [ -n "$current_dir" ]; then
  repo_root=$(cd "$current_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
  dir_display=$(basename "$repo_root")
  add_part "$(printf '📁 %b%s%b' "$CYAN" "$dir_display" "$RST")"
fi

# 🌿 Git branch + staged/modified
if [ -n "$current_dir" ] && cd "$current_dir" 2>/dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')

  git_str="$branch"
  [ "$staged" -gt 0 ] && git_str="${git_str} ${GREEN}+${staged}${RST}"
  [ "$modified" -gt 0 ] && git_str="${git_str} ${YELLOW}~${modified}${RST}"
  add_part "$(printf '🌿 %s' "$git_str")"
fi

# 🌳 Worktree (if active)
[ -n "$worktree" ] && add_part "$(printf '🌳 %s' "$worktree")"

# 🕐 Session duration
[ -n "$session_duration" ] && add_part "$(printf '🕐 %b%s%b' "$DIM" "$session_duration" "$RST")"

# ⚡ Agent name
[ -n "$agent_name" ] && add_part "$(printf '%b⚡%s%b' "$MAGENTA" "$agent_name" "$RST")"

# Session name
[ -n "$session_name" ] && add_part "$(printf '%b[%s]%b' "$DIM" "$session_name" "$RST")"

# Output style (only if not default)
[ -n "$output_style" ] && [ "$output_style" != "default" ] && add_part "$(printf '%b%s%b' "$DIM" "$output_style" "$RST")"

printf '%b' "$parts"
