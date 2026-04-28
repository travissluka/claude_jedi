#!/bin/bash
# Claude Code status line — reads JSON from stdin (piped by Claude Code)
# Shows: cwd+branch | model effort | context bar | 5h rate bar (time remaining)

# --- Config ---
CTX_BAR_WIDTH=20
RATE_BAR_WIDTH=10

# ANSI colors
RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
BRIGHT_BLACK='\033[90m'

SEP="${BRIGHT_BLACK}│${RESET}"

# --- Read JSON from stdin, extract all fields in one jq call ---
input=$(cat)
eval "$(echo "$input" | jq -r '
  @sh "cwd=\(.workspace.current_dir // "")",
  @sh "model_display=\(.model.display_name // "")",
  @sh "ctx_pct=\(.context_window.used_percentage // 0 | floor)",
  @sh "rate_5h=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "rate_5h_resets=\(.rate_limits.five_hour.resets_at // "")",
  @sh "proj_dir=\(.workspace.project_dir // "")"
' 2>/dev/null)"

# --- Context bar ---
[[ -z "$ctx_pct" ]] && ctx_pct=0
filled=$(( (ctx_pct * CTX_BAR_WIDTH) / 100 ))
empty=$(( CTX_BAR_WIDTH - filled ))

if [[ $ctx_pct -ge 85 ]]; then bar_color="$RED"
elif [[ $ctx_pct -ge 60 ]]; then bar_color="$YELLOW"
else bar_color="$GREEN"; fi

printf -v f "%${filled}s"; printf -v e "%${empty}s"
ctx_bar="${BRIGHT_BLACK}[${bar_color}${f// /█}${BRIGHT_BLACK}${e// /░}]${RESET} ${ctx_pct}%"

# --- Effort level (from settings, not in stdin JSON — max doesn't persist) ---
effort=$(jq -r '.effortLevel // "normal"' "$HOME/.claude/settings.json" 2>/dev/null)
case "$effort" in
    low)    effort_display="${BRIGHT_BLACK}low${RESET}" ;;
    medium) effort_display="${BRIGHT_BLACK}medium${RESET}" ;;
    normal) effort_display="" ;;
    high)   effort_display="${CYAN}high${RESET}" ;;
    xhigh)  effort_display="${MAGENTA}xhigh${RESET}" ;;
    max)    effort_display="${MAGENTA}${BOLD}max${RESET}" ;;
    *)      effort_display="" ;;
esac

# --- Rate limit (5h window) with bar and time remaining ---
rate_display=""
if [[ -n "$rate_5h" ]]; then
    rate_int=$(printf '%.0f' "$rate_5h")

    if [[ $rate_int -ge 70 ]]; then rate_color="$RED"
    elif [[ $rate_int -ge 40 ]]; then rate_color="$YELLOW"
    else rate_color="$GREEN"; fi

    r_filled=$(( (rate_int * RATE_BAR_WIDTH) / 100 ))
    r_empty=$(( RATE_BAR_WIDTH - r_filled ))

    printf -v rf "%${r_filled}s"; printf -v re "%${r_empty}s"
    rate_bar="${BRIGHT_BLACK}[${rate_color}${rf// /█}${BRIGHT_BLACK}${re// /░}]${RESET}"

    # Time remaining until reset
    time_left=""
    if [[ -n "$rate_5h_resets" ]]; then
        remaining=$(( rate_5h_resets - $(date +%s) ))
        if [[ $remaining -gt 0 ]]; then
            hours=$(( remaining / 3600 ))
            mins=$(( (remaining % 3600) / 60 ))
            [[ $hours -gt 0 ]] && time_left="${hours}h${mins}m" || time_left="${mins}m"
        fi
    fi

    rate_display="5h ${rate_bar} ${rate_int}%"
    [[ -n "$time_left" ]] && rate_display="${rate_display} ${BRIGHT_BLACK}(${time_left})${RESET}"
fi

# --- Git branch ---
git_branch=""
if [[ -n "$proj_dir" ]] && command -v git &>/dev/null; then
    git_branch=$(git -C "$proj_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# --- cwd display ---
cwd_display=""
if [[ -n "$cwd" ]]; then
    dir_name="${cwd/#$HOME/\~}"
    branch_part=""
    [[ -n "$git_branch" && "$git_branch" != "HEAD" ]] && branch_part="${CYAN} ${git_branch}${RESET}"
    host_part="${BRIGHT_BLACK}$(hostname -s)${RESET}"
    cwd_display="${host_part}${BRIGHT_BLACK}:${RESET}${GREEN}${BOLD}${dir_name}${RESET}${branch_part}"
fi

# --- Assemble output ---
parts=()
[[ -n "$cwd_display" ]] && parts+=("$cwd_display")
model_part="${BRIGHT_BLACK}${model_display}${RESET}"
[[ -n "$effort_display" ]] && model_part="${model_part} ${effort_display}"
[[ -n "$model_display" ]] && parts+=("$model_part")
parts+=("$ctx_bar")
[[ -n "$rate_display" ]] && parts+=("$rate_display")

output=""
for part in "${parts[@]}"; do
    [[ -n "$output" ]] && output="${output}  ${SEP}  ${part}" || output="${part}"
done

printf '%b\n' "$output"
