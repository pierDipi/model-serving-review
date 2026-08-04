#!/usr/bin/env bash
# run-evals.sh — Sets up synthetic repos from fixtures and prepares them for skill evaluation.
#
# Usage:
#   ./run-evals.sh [fixture-name ...]
#
# With no arguments, runs ALL fixtures. With arguments, runs only the named ones.
# Each fixture script creates a git repo with planted violations, commits an initial
# state, then commits the change-under-review. The skill's fetch-context.sh is then
# run to produce the review directory.
#
# Output: For each fixture, prints a JSON line with:
#   {"fixture": "name", "repo_dir": "/tmp/...", "review_dir": "/tmp/...", "metadata": "/tmp/.../metadata.json"}
#
# The caller (subagent or human) then invokes the skill against each repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
SKILL_DIR="$(cd "$SCRIPT_DIR/../skills/model-serving-review" && pwd -P)"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$RESULTS_DIR"

if [[ $# -gt 0 ]]; then
  FIXTURES=("$@")
else
  FIXTURES=()
  for f in "$FIXTURES_DIR"/*.sh; do
    name=$(basename "$f" .sh)
    [[ "$name" == "common" ]] && continue
    FIXTURES+=("$name")
  done
fi

echo "Running ${#FIXTURES[@]} fixtures..."
echo "Results: $RESULTS_DIR"
echo "---"

PASS=0
FAIL=0
SKIP=0

for name in "${FIXTURES[@]}"; do
  fixture_script="$FIXTURES_DIR/${name}.sh"
  if [[ ! -f "$fixture_script" ]]; then
    echo "SKIP $name — fixture script not found"
    ((SKIP++))
    continue
  fi

  echo -n "SETUP $name ... "

  # Run the fixture script to create the repo
  repo_dir=$(bash "$fixture_script" 2>/dev/null) || {
    echo "FAIL (fixture script errored)"
    ((FAIL++))
    continue
  }

  if [[ ! -d "$repo_dir/.git" ]]; then
    echo "FAIL (not a git repo: $repo_dir)"
    ((FAIL++))
    continue
  fi

  # Run fetch-context.sh to create the review directory (fixtures always have 2 commits)
  metadata_path=$(cd "$repo_dir" && bash "$SKILL_DIR/scripts/fetch-context.sh" --base HEAD~1 2>/dev/null) || {
    echo "FAIL (fetch-context.sh errored)"
    ((FAIL++))
    continue
  }

  review_dir=$(dirname "$metadata_path")

  # Save fixture info for the grader
  mkdir -p "$RESULTS_DIR/$name"
  jq -n \
    --arg fixture "$name" \
    --arg repo_dir "$repo_dir" \
    --arg review_dir "$review_dir" \
    --arg metadata "$metadata_path" \
    '{fixture: $fixture, repo_dir: $repo_dir, review_dir: $review_dir, metadata: $metadata}' \
    > "$RESULTS_DIR/$name/setup.json"

  echo "OK (repo=$repo_dir review=$review_dir)"
  ((PASS++))
done

echo "---"
echo "Setup complete: $PASS OK, $FAIL failed, $SKIP skipped"
echo "Results directory: $RESULTS_DIR"
echo ""
echo "Next steps:"
echo "  1. For each fixture, invoke the skill: /model-serving-review --base HEAD~1"
echo "     from within the fixture's repo_dir"
echo "  2. Save the skill output to \$RESULTS_DIR/<fixture>/output.json"
echo "  3. Run: bash evals/grade-results.sh \$RESULTS_DIR"
