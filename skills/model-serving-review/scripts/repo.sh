#!/usr/bin/env bash
set -euo pipefail

# repo.sh — Read-only repo operations for model-serving-review agents.
# Fixed command whitelist. Path containment for cat/ls.
# Arguments passed via "$@" — no eval, no interpolation.

WORK_DIR="${1:?Usage: repo.sh <work_dir> <command> [args...]}"
CMD="${2:?Usage: repo.sh <work_dir> <command> [args...]}"
shift 2

[[ -d "$WORK_DIR" ]] || { echo "error: not a directory: $WORK_DIR" >&2; exit 1; }
WORK_DIR=$(cd "$WORK_DIR" && pwd -P)

safe_path() {
  local resolved
  resolved=$(realpath -m "$WORK_DIR/$1" 2>/dev/null) \
    || { echo "error: invalid path: $1" >&2; exit 1; }
  [[ "$resolved" == "$WORK_DIR"/* || "$resolved" == "$WORK_DIR" ]] \
    || { echo "error: path outside work_dir: $1" >&2; exit 1; }
  printf '%s' "$resolved"
}

case "$CMD" in
  diff) git -C "$WORK_DIR" diff "$@" ;;
  log)  git -C "$WORK_DIR" log "$@" ;;
  show) git -C "$WORK_DIR" show "$@" ;;
  cat)
    [[ $# -ge 1 ]] || { echo "error: cat requires a path" >&2; exit 1; }
    resolved=$(safe_path "$1") || exit 1
    cat "$resolved"
    ;;
  ls)
    if [[ $# -eq 0 ]]; then
      ls "$WORK_DIR"
    else
      resolved=$(safe_path "$1") || exit 1
      ls "$resolved"
    fi
    ;;
  grep)
    git -C "$WORK_DIR" grep "$@"
    ;;
  ls-files)
    git -C "$WORK_DIR" ls-files "$@"
    ;;
  pr-meta)
    [[ $# -ge 2 ]] || { echo "error: pr-meta requires <pr-number> <owner/repo>" >&2; exit 1; }
    [[ "$1" =~ ^[0-9]+$ ]] || { echo "error: pr-number must be numeric" >&2; exit 1; }
    [[ "$2" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]] || { echo "error: invalid repo format" >&2; exit 1; }
    gh pr view "$1" --repo "$2" --json title,labels,state,baseRefName,headRefName,files
    ;;
  pr-search)
    [[ $# -ge 2 ]] || { echo "error: pr-search requires <owner/repo> <query>" >&2; exit 1; }
    [[ "$1" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]] || { echo "error: invalid repo format" >&2; exit 1; }
    gh search prs --repo "$1" "$2" --json title,url,state
    ;;
  *)
    echo "error: unknown command: $CMD (allowed: diff, log, show, cat, ls, grep, ls-files, pr-meta, pr-search)" >&2
    exit 1
    ;;
esac
