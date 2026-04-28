#!/bin/bash
# PreToolUse hook: block Bash commands that match forbidden patterns.
# Reads JSON from stdin, extracts tool_input.command, checks against patterns.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# Blocked patterns (one per line: regex + reason)
declare -A blocked=(
  ['^\s*echo\s+\$']='Use printenv instead of echo $VAR'
  ['^\s*echo\s+"?\$']='Use printenv instead of echo "$VAR"'
  ['^\s*echo\s+"\$']='Use printenv instead of echo "$VAR"'
  ['(^|\s)source\s+']='Do not use source — see CLAUDE.md for env setup'
)

for pattern in "${!blocked[@]}"; do
  if printf '%s' "$cmd" | grep -qP "$pattern"; then
    reason="${blocked[$pattern]}"
    printf '{"decision":"block","reason":"%s"}\n' "$reason"
    exit 2
  fi
done

exit 0
