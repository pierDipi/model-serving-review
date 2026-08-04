#!/usr/bin/env bash
# common.sh — Shared helpers for eval fixture scripts.
# Source this from each fixture script.
set -euo pipefail

FIXTURE_NAME="${FIXTURE_NAME:?Set FIXTURE_NAME before sourcing common.sh}"

# Create a temp repo, init git, configure it, and cd into it.
# Returns the repo path via REPO_DIR.
init_repo() {
  REPO_DIR=$(mktemp -d "/tmp/eval-fixture-${FIXTURE_NAME}-XXXXXX")
  cd "$REPO_DIR"
  git init -q
  git config user.email "eval@test.local"
  git config user.name "Eval Bot"

  # Simulate a kserve-like remote so fetch-context.sh detects the repo correctly.
  local remote="${1:-https://github.com/kserve/kserve.git}"
  git remote add origin "$remote"
}

# Write a file relative to REPO_DIR, creating parent dirs as needed.
write_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

# Commit all current changes with a message.
commit() {
  git add -A
  git commit -q -m "${1:-initial}" --allow-empty
}

# Emit the repo path — the harness reads this.
emit_repo() {
  echo "$REPO_DIR"
}
