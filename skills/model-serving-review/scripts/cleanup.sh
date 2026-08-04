#!/usr/bin/env bash
set -euo pipefail

# cleanup.sh — Remove a model-serving-review temp directory.
# Only deletes paths matching /tmp/model-serving-review-*.

DIR="${1:?Usage: cleanup.sh <review_dir>}"

[[ "$DIR" == /tmp/model-serving-review-* ]] || {
  echo "error: refusing to delete path outside /tmp/model-serving-review-*: $DIR" >&2
  exit 1
}

[[ -d "$DIR" ]] || { echo "Already cleaned up: $DIR"; exit 0; }

rm -rf "$DIR"
echo "Cleaned up: $DIR"
