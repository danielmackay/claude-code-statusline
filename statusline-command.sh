#!/bin/sh
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
worktree=$(echo "$input" | jq -r '.worktree.name // empty')
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
current_dir=$(echo "$input" | jq -r '.worktree.original_cwd // empty')
rl_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | awk '{printf "%.0f", $1}')
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$used" ]; then
  used_display=$(printf "%.0f" "$used")
  usage_str="${used_display}%"
else
  usage_str="0%"
fi

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

git_str=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')

  git_str="$branch"
  [ "$staged" -gt 0 ] && git_str="${git_str} $(printf "${GREEN}+${staged}${RESET}")"
  [ "$modified" -gt 0 ] && git_str="${git_str} $(printf "${YELLOW}~${modified}${RESET}")"
else
  git_str="no branch"
fi


if [ -n "$total_cost" ]; then
  cost_display=$(awk "BEGIN { printf \"%.2f\", $total_cost }")
  block_str="\$${cost_display}"
else
  block_str="\$0.00"
fi

MARKER='\033[1;97m'

# Percent of the window that has elapsed, i.e. where usage would sit if spread
# evenly across it. Prints nothing when the reset time is missing or outside the
# window, so the bar falls back to having no pace marker.
window_elapsed_pct() {
  reset_ts="$1"
  window_secs="$2"
  case "$reset_ts" in ''|*[!0-9]*) return ;; esac
  now=$(date +%s)
  remaining=$(( reset_ts - now ))
  [ "$remaining" -lt 0 ] && return
  [ "$remaining" -gt "$window_secs" ] && return
  printf "%s" $(( (window_secs - remaining) * 100 / window_secs ))
}

# Draws the usage bar. When a pace percent is given, the cell where even usage
# would be right now becomes a bright ┃: fill past it means burning faster than
# the window allows, fill short of it means there is headroom.
make_bar() {
  pct="$1"
  pace="$2"
  color="$3"
  width=10
  filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  marker_at=-1
  if [ -n "$pace" ]; then
    marker_at=$(( pace * width / 100 ))
    [ "$marker_at" -ge "$width" ] && marker_at=$(( width - 1 ))
  fi
  bar=""
  i=0
  while [ $i -lt $width ]; do
    if [ $i -eq $marker_at ]; then bar="${bar}${MARKER}┃${RESET}${color}"
    elif [ $i -lt $filled ]; then bar="${bar}█"
    else bar="${bar}░"
    fi
    i=$(( i + 1 ))
  done
  printf "%s" "$bar"
}

format_rl() {
  pct="$1"
  reset_ts="$2"
  label="$3"
  window_secs="$4"
  [ -z "$pct" ] && return
  reset_time=$(date -r "$reset_ts" "+%-I:%M%p" 2>/dev/null || date -d "@$reset_ts" "+%-I:%M%p" 2>/dev/null)
  pace=$(window_elapsed_pct "$reset_ts" "$window_secs")
  # Colour by burn rate against even usage. Up to 10 points over pace is yellow
  # so a small burst early in the window doesn't flash red. Without a pace
  # there is nothing to compare against, so it stays green.
  color="$GREEN"
  if [ -n "$pace" ]; then
    if [ "$pct" -gt $(( pace + 10 )) ]; then color="$RED"
    elif [ "$pct" -gt "$pace" ]; then color="$YELLOW"
    fi
  fi
  bar=$(make_bar "$pct" "$pace" "$color")
  printf "${color}${label} ${bar} ${pct}%% resets ${reset_time}${RESET}"
}

rate_limit_str=""
rate_limit_str="${rate_limit_str}$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h" 18000)"
# rate_limit_str="${rate_limit_str}$(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d" 604800)"

# Repo and worktree come from git, not the directory name: externally managed
# worktrees (e.g. Orca's ~/orca/workspaces/<repo>/<worktree>) live outside the
# repo, so the toplevel basename is the worktree, not the repo. The common git
# dir always belongs to the main checkout, so its parent names the repo.
[ -z "$current_dir" ] && current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$current_dir" ] && current_dir="."
dir_display=""
git_worktree=""
if common_dir=$(cd "$current_dir" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  git_dir=$(cd "$current_dir" && git rev-parse --path-format=absolute --git-dir 2>/dev/null)
  case "$(basename "$common_dir")" in
    .git) dir_display=$(basename "$(dirname "$common_dir")") ;;
    *) dir_display=$(basename "$common_dir" .git) ;; # bare repo
  esac
  # A linked worktree has its own git dir apart from the common one. Claude
  # managed worktrees are reported in the JSON instead (original_cwd is the main repo).
  if [ -n "$git_dir" ] && [ "$git_dir" != "$common_dir" ]; then
    git_worktree=$(basename "$(cd "$current_dir" && git rev-parse --show-toplevel 2>/dev/null)")
  fi
fi
[ -z "$dir_display" ] && dir_display=$(basename "$(cd "$current_dir" 2>/dev/null && pwd)")

if [ -n "$worktree" ]; then
  worktree_str="${worktree}"
elif [ -n "$git_worktree" ]; then
  worktree_str="${git_worktree}"
else
  worktree_str="no worktree"
fi

if [ -n "$effort" ]; then
  printf "🤖 %s | 💪 %s | 🧠 %s | 💰 %s | ⏱️ %s\n📁 %s | 🌳 %s | 🌿 %s" "$model" "$effort" "$usage_str" "$block_str" "$rate_limit_str" "$dir_display" "$worktree_str" "$git_str"
else
  printf "🤖 %s | 🧠 %s | 💰 %s | ⏱️ %s\n📁 %s | 🌳 %s | 🌿 %s" "$model" "$usage_str" "$block_str" "$rate_limit_str" "$dir_display" "$worktree_str" "$git_str"
fi
