#!/usr/bin/env bash
# claude-code-statusline — Claude usage variant
# Shows: cwd | branch | model | context | rate limits | cost | effort
#
# Usage: Set in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash ~/.claude/claude-pro-usage.sh" }

set -euo pipefail

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')
parts=()
SEP=$' \033[90m|\033[0m '

# CWD basename (white)
if [[ -n "${cwd:-}" ]]; then
  parts+=("$(printf '\033[37m📂 %s\033[0m' "$(basename "$cwd")")")
fi

# Git branch — 🏠 (green) for main/master, ⎇ (cyan) for everything else
if [[ -n "${cwd:-}" ]]; then
  branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || true)
  if [[ -n "$branch" ]]; then
    case "$branch" in
      main|master) parts+=("$(printf '\033[32m🏠 %s\033[0m' "$branch")") ;;
      *)           parts+=("$(printf '\033[36m⎇ %s\033[0m' "$branch")") ;;
    esac
  fi
fi

# Model (light purple)
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
if [[ -n "${model_name:-}" ]]; then
  parts+=("$(printf '\033[38;5;147m🧠 %s\033[0m' "$model_name")")
fi

# Context window — progress bar + % (color-coded green/yellow/red)
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [[ -n "${used_pct:-}" ]]; then
  pct_int=$(printf '%.0f' "$used_pct")
  if [[ "$pct_int" -ge 80 ]]; then ctx_color='\033[31m'
  elif [[ "$pct_int" -ge 50 ]]; then ctx_color='\033[33m'
  else ctx_color='\033[32m'; fi
  bar_width=10
  filled=$(( pct_int * bar_width / 100 ))
  empty=$(( bar_width - filled ))
  filled_bar=""; empty_bar=""
  for ((i=0; i<filled; i++)); do filled_bar+=$(printf '\xe2\x96\x88'); done
  for ((i=0; i<empty; i++)); do empty_bar+=$(printf '\xe2\x96\x92'); done
  parts+=("$(printf "${ctx_color}🔋 %s\033[90m%s${ctx_color} %s%%\033[0m" "$filled_bar" "$empty_bar" "$pct_int")")
fi

# Rate limits — % + bar + window label + reset time (Claude.ai Pro/Max only)
# Format: 🚦 16% ██▒▒▒▒▒▒▒▒ 5h ↺4h24m | 1% █▒▒▒▒▒▒▒▒▒ 7d ↺4d9h
five_h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_h_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_d_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [[ -n "${five_h_pct:-}" ]] || [[ -n "${seven_d_pct:-}" ]]; then
  now_ts=$(date +%s)

  _rl_segment() {
    local label="$1" val="$2" resets_at="$3"
    [[ -z "$val" ]] && return
    local val_int; val_int=$(printf '%.0f' "$val")
    local rl_color
    if [[ "$val_int" -ge 80 ]]; then rl_color='\033[31m'
    elif [[ "$val_int" -ge 50 ]]; then rl_color='\033[33m'
    else rl_color='\033[32m'; fi
    local bar_width=10
    local filled=$(( (val_int * bar_width + 50) / 100 ))
    [[ "$val_int" -gt 0 && "$filled" -eq 0 ]] && filled=1
    local empty=$(( bar_width - filled ))
    local filled_bar="" empty_bar=""
    for ((i=0; i<filled; i++)); do filled_bar+=$(printf '\xe2\x96\x88'); done
    for ((i=0; i<empty; i++)); do empty_bar+=$(printf '\xe2\x96\x92'); done
    local reset_str=""
    if [[ -n "${resets_at:-}" ]] && [[ "$resets_at" -gt "$now_ts" ]]; then
      local remaining=$(( resets_at - now_ts ))
      local r_d=$(( remaining / 86400 ))
      local r_h=$(( (remaining % 86400) / 3600 ))
      local r_m=$(( (remaining % 3600) / 60 ))
      if [[ "$r_d" -gt 0 ]]; then reset_str=" ↺${r_d}d${r_h}h"
      elif [[ "$r_h" -gt 0 ]]; then reset_str=" ↺${r_h}h${r_m}m"
      else reset_str=" ↺${r_m}m"; fi
    fi
    printf "${rl_color}%s%% %s\033[90m%s${rl_color} %s%s\033[0m" "$val_int" "$filled_bar" "$empty_bar" "$label" "$reset_str"
  }

  seg5=$(_rl_segment "5h" "$five_h_pct" "$five_h_resets")
  seg7=$(_rl_segment "7d" "$seven_d_pct" "$seven_d_resets")

  rl_out=""
  [[ -n "$seg5" ]] && rl_out="$seg5"
  [[ -n "$seg5" && -n "$seg7" ]] && rl_out+=" $(printf '\033[90m|\033[0m') "
  [[ -n "$seg7" ]] && rl_out+="$seg7"
  [[ -n "$rl_out" ]] && parts+=("$(printf '🚦 %s' "$rl_out")")
fi

# Cost (magenta)
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [[ -n "${total_cost:-}" ]]; then
  formatted=$(awk -v c="$total_cost" 'BEGIN { printf "%.3f", c }')
  parts+=("$(printf '\033[35m💰 $%s\033[0m' "$formatted")")
fi

# Effort level — color-coded by intensity (💭 low=green … max=red)
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
if [[ -n "${effort_level:-}" ]]; then
  case "$effort_level" in
    low)    eff_color='\033[32m' ;;
    medium) eff_color='\033[36m' ;;
    high)   eff_color='\033[33m' ;;
    xhigh)  eff_color='\033[35m' ;;
    max)    eff_color='\033[31m' ;;
    *)      eff_color='\033[37m' ;;
  esac
  parts+=("$(printf "${eff_color}💭 %s\033[0m" "$effort_level")")
fi

# Output
output=""
for i in "${!parts[@]}"; do
  [[ "$i" -gt 0 ]] && output+="$SEP"
  output+="${parts[$i]}"
done
printf '%s' "$output"
