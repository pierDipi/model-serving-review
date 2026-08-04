#!/usr/bin/env bash
set -euo pipefail

# validate-cmd.sh — PreToolUse hook for reviewer subagents.
# Reads Claude Code hook JSON from stdin, extracts the Bash command,
# and validates it against a strict whitelist.
# Outputs permissionDecision JSON to auto-allow or auto-deny.

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
[[ "$AGENT_TYPE" != model-serving-review:* ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Command matches reviewer whitelist"}}'
  exit 0
}

deny() {
  local reason="${1:-Command not in reviewer whitelist}"
  reason="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

# Block command substitution and process substitution
[[ "$COMMAND" == *'`'* ]]  && deny "Backtick substitution not allowed"
[[ "$COMMAND" == *'$('* ]] && deny "Command substitution not allowed"
[[ "$COMMAND" == *'<('* ]] && deny "Process substitution not allowed"
[[ "$COMMAND" == *'>('* ]] && deny "Process substitution not allowed"

# Block output redirection (except >/dev/null, 2>/dev/null, 2>&1)
REDIR_STRIPPED=$(echo "$COMMAND" | sed -E 's/[12]?>[[:space:]]*\/dev\/null//g; s/[12]?>&[12]//g')
[[ "$REDIR_STRIPPED" == *'>'* ]] && deny "Output redirection not allowed"

# Safe pipe targets: read-only text processors that cannot execute commands.
# Intentionally excludes awk (system()), sed (e flag), tee (writes files), xargs (executes).
SAFE_PIPE='^(grep|egrep|fgrep|head|tail|wc|sort|uniq|cut|tr|nl|column|cat|fmt|fold|rev|tac)([[:space:]]|$)'

# Validate the first command in a pipeline against the whitelist
valid_first_cmd() {
  local cmd="$1"
  # Strip trailing 2>/dev/null for matching
  cmd=$(echo "$cmd" | sed -E 's/[[:space:]]*2>[[:space:]]*\/dev\/null[[:space:]]*$//')
  cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  [[ -z "$cmd" ]] && return 0

  # repo.sh wrapper
  [[ "$cmd" =~ ^(bash[[:space:]]+)?[.a-zA-Z0-9/_-]*/scripts/repo\.sh[[:space:]] ]] && return 0
  # wc on review dir
  [[ "$cmd" =~ ^wc[[:space:]].*[[:space:]]/tmp/model-serving-review- ]] && return 0
  # gh routed through repo.sh pr-meta/pr-search (no raw gh allowed)

  # Read-only filesystem commands (agents already have Read tool access;
  # redirects and command substitution are blocked above)
  if [[ "$cmd" =~ ^find([[:space:]]|$) ]]; then
    [[ "$cmd" =~ -exec|-execdir|-delete|-ok ]] && return 1
    return 0
  fi
  [[ "$cmd" =~ ^(grep|egrep|fgrep|ls|cat|head|tail|wc|file|stat|cd)([[:space:]]|$) ]] && return 0

  # Read-only git subcommands
  local SAFE_GIT='^git[[:space:]]+(log|show|diff|status|branch|tag|rev-parse|rev-list|describe|shortlog|blame|ls-files|ls-tree|cat-file|name-rev|merge-base)([[:space:]]|$)'
  [[ "$cmd" =~ $SAFE_GIT ]] && return 0

  return 1
}

# Validate all pipe targets in a pipeline
valid_pipes() {
  local pipeline="$1"
  local rest
  rest=$(echo "$pipeline" | sed 's/^[^|]*//')
  while [[ "$rest" == '|'* ]]; do
    rest="${rest#|}"
    local target
    target=$(echo "$rest" | awk -F'[|]' '{print $1}' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    # Strip trailing 2>/dev/null
    target=$(echo "$target" | sed -E 's/[[:space:]]*2>[[:space:]]*\/dev\/null[[:space:]]*$//')
    if ! [[ "$target" =~ $SAFE_PIPE ]]; then
      return 1
    fi
    rest=$(echo "$rest" | sed 's/^[^|]*//')
  done
  return 0
}

# Split on ; && || and validate each segment independently.
# Note: splitting is naive (doesn't respect quoting), but false rejections
# are safe — agents retry with separate tool calls.
while IFS= read -r segment; do
  segment=$(echo "$segment" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  [[ -z "$segment" ]] && continue

  first=$(echo "$segment" | awk -F'[|]' '{print $1}')
  valid_first_cmd "$first" || deny "Command not in reviewer whitelist. Use: bash \$scripts_dir/repo.sh \$work_dir <diff|log|show|grep|ls-files|cat|ls|pr-meta|pr-search> [args]"
  valid_pipes "$segment"   || deny "Unsafe pipe target. Allowed: grep, head, tail, wc, sort, uniq, cut, tr."
done < <(printf '%s\n' "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g')

allow
