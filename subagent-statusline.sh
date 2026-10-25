#!/bin/sh
# Renders each row of the agent panel below the prompt as:
#   <agent type> · 🤖 <model> | 💪 <effort> · <activity>          🧠 <context %> · <elapsed>
# with the context % and clock right-aligned. Claude Code pipes {columns, tasks[]} on stdin and
# reads back one {"id","content"} JSON line per row. A task we print nothing for keeps Claude
# Code's default row, so a missing field degrades to a shorter row rather than a blank one.

if ! command -v jq >/dev/null 2>&1; then
  echo "subagent-statusline: jq not found on PATH" >&2
  exit 1
fi

jq -c '
  # Seconds -> "42s", "8m 8s", "1h 5m".
  def short_duration:
    if . >= 3600 then "\(. / 3600 | floor)h \(. % 3600 / 60 | floor)m"
    elif . >= 60 then "\(. / 60 | floor)m \(. % 60)s"
    else "\(.)s" end;

  # The task model may arrive as an id ("claude-opus-5-5[1m]", "claude-sonnet-4-5-20250929") or
  # as an object; render ids the way the main status line shows display names ("Opus 5.5").
  def model_name:
    (if type == "object" then (.display_name // .id // "") else tostring end)
    | if test("^claude-") then
        sub("^claude-"; "") | sub("\\[.*\\]$"; "") | sub("-[0-9]{8}$"; "")
        | split("-")
        | ((.[0][0:1] | ascii_upcase) + .[0][1:]) as $family
        | if length > 1 then "\($family) \(.[1:] | join("."))" else $family end
      else . end;

  # Emojis are one codepoint but two columns wide; count them so layout measures columns.
  def width: length + ([scan("[🤖💪🧠]")] | length);

  (.columns // 80) as $cols
  | now as $now
  | (.tasks // [])[]
  | select(.id != null)
  # Claude Code sends no `name` for plain subagents, so the agent type ("builder",
  # "general-purpose") is what identifies the row.
  | (.name // .agentType // "agent") as $name
  | ([ (if .model != null and .model != "" then "🤖 \(.model | model_name)" else empty end),
       (if .effort != null and .effort != "" then "💪 \(.effort)" else empty end) ]
     | if length > 0 then " · " + join(" | ") else "" end) as $model
  # Only startTime is sent, no end time, so a finished task would keep counting up: show the
  # clock while the task runs and drop it once the status moves on.
  | ([ (if (.tokenCount | type) == "number" and (.contextWindowSize | type) == "number" and .contextWindowSize > 0
        then "🧠 \([(.tokenCount * 100 / .contextWindowSize | round), 100] | min)%" else empty end),
       (if (.startTime | type) == "number" and (.status == null or .status == "running")
        then [($now - .startTime / 1000 | floor), 0] | max | short_duration else empty end) ]
     | join(" · ")) as $right
  # One column of slack keeps the row off the terminal edge, where it would wrap.
  | ($cols - 1) as $usable
  | (if $right == "" then 0 else ($right | width) + 2 end) as $right_min
  # On a narrow row, give up the model first so the agent type and the right-hand group fit.
  | (if ("\($name)\($model)" | width) + $right_min <= $usable then $model else "" end) as $model
  # `label` is what the agent is doing now: it starts as the spawn description, then tracks
  # progress.
  | ($usable - ("\($name)\($model)" | width) - $right_min - 3) as $room
  | (.label // .description // "") as $text
  | (if $text == "" or $room < 4 then ""
     elif ($text | length) > $room then " · \($text[0:$room - 1])…"
     else " · \($text)" end) as $text_part
  | "\($name)\($model)\($text_part)" as $left
  | (if $right == "" then $left
     else $left + (" " * ([$usable - ($left | width) - ($right | width), 2] | max)) + $right
     end) as $content
  | {id, content: $content}
'
