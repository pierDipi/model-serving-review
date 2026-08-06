#!/usr/bin/env bash
# run-skill.sh — Drive the model-serving-review skill headlessly over set-up fixtures.
#
# Usage: ./run-skill.sh [results-dir]
#
# For each <results-dir>/<fixture>/setup.json produced by run-evals.sh, this runs
#   claude -p "/model-serving-review --base HEAD~1"
# inside the fixture's repo, then parses the skill's markdown report table into the
# JSON findings array the grader expects at <results-dir>/<fixture>/output.json:
#   [{"rule_id": "...", "severity": "...", "file": "...", "finding": "..."}]
#
# Env knobs:
#   JOBS        parallel fixtures (default 3)
#   CLAUDE_BIN  path to the claude binary (default: resolved from PATH)
#   PLUGIN_DIR  plugin dir to load (default: cached model-serving-review plugin)
#   MODEL       optional --model override passed to claude
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RESULTS_DIR="${1:-$(ls -1dt "$SCRIPT_DIR"/results/*/ 2>/dev/null | head -1)}"
[[ -n "$RESULTS_DIR" && -d "$RESULTS_DIR" ]] || { echo "error: no results dir (run run-evals.sh first)" >&2; exit 1; }

JOBS="${JOBS:-3}"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude)}"
# The skill is a plugin command; from a fixture repo in /tmp it must be loaded explicitly.
DEFAULT_PLUGIN=$(ls -1d "$HOME"/.claude/plugins/cache/model-serving-review/model-serving-review/*/ 2>/dev/null | sort -V | tail -1)
PLUGIN_DIR="${PLUGIN_DIR:-${DEFAULT_PLUGIN%/}}"
MODEL="${MODEL:-}"

[[ -x "$CLAUDE_BIN" || -n "$CLAUDE_BIN" ]] || { echo "error: claude binary not found; set CLAUDE_BIN" >&2; exit 1; }
[[ -n "$PLUGIN_DIR" && -d "$PLUGIN_DIR" ]] || { echo "error: plugin dir not found; set PLUGIN_DIR" >&2; exit 1; }

export CLAUDE_BIN PLUGIN_DIR MODEL

# Parse the skill's markdown report (on stdin) into the findings JSON array (on stdout).
# Report rows look like:  | 1 | CTL-010 | MUST | `path/to/file.go` | Finding text |
report_to_json() {
  awk -F'|' '
    {
      for (i = 1; i <= NF; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
    }
    $3 ~ /^[A-Z]+-[0-9]+$/ {
      rule = $3; sev = $4; file = $5; finding = $6
      gsub(/`/, "", file)
      print rule "\t" sev "\t" file "\t" finding
    }
  ' | jq -R -s '
      split("\n")
      | map(select(length > 0) | split("\t")
            | {rule_id: .[0], severity: .[1], file: .[2], finding: (.[3] // "")})
    '
}
export -f report_to_json

run_one() {
  local fixture_dir="$1"
  local fixture setup repo_dir raw result
  fixture=$(basename "$fixture_dir")
  setup="$fixture_dir/setup.json"
  [[ -f "$setup" ]] || { echo "SKIP $fixture (no setup.json)"; return 0; }
  repo_dir=$(jq -r '.repo_dir' "$setup")
  [[ -d "$repo_dir/.git" ]] || { echo "SKIP $fixture (repo gone: $repo_dir)"; return 0; }

  local model_args=()
  [[ -n "$MODEL" ]] && model_args=(--model "$MODEL")

  raw="$fixture_dir/skill-raw.json"
  if ! ( cd "$repo_dir" && timeout 900 "$CLAUDE_BIN" \
           -p "/model-serving-review --base HEAD~1" \
           --output-format json --dangerously-skip-permissions \
           --plugin-dir "$PLUGIN_DIR" "${model_args[@]}" ) > "$raw" 2>"$fixture_dir/skill.err"; then
    echo "FAIL $fixture (claude errored/timed out; see $fixture_dir/skill.err)"
    return 0
  fi

  result=$(jq -r '.result // empty' "$raw" 2>/dev/null)
  if [[ -z "$result" ]]; then
    echo "FAIL $fixture (no .result in output)"
    return 0
  fi
  printf '%s\n' "$result" | report_to_json > "$fixture_dir/output.json"
  echo "OK   $fixture ($(jq 'length' "$fixture_dir/output.json") findings)"
}
export -f run_one

echo "Running skill over fixtures in: $RESULTS_DIR"
echo "  claude=$CLAUDE_BIN  plugin=$PLUGIN_DIR  jobs=$JOBS${MODEL:+  model=$MODEL}"
echo "---"

# Fan out across fixtures with bounded parallelism.
find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 \
  | xargs -0 -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

echo "---"
echo "Done. Grade with: bash $SCRIPT_DIR/grade-results.sh $RESULTS_DIR"
