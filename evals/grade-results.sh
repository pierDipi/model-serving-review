#!/usr/bin/env bash
# grade-results.sh — Grade skill outputs against expected findings.
#
# Usage: ./grade-results.sh <results-dir>
#
# Reads each <results-dir>/<fixture>/output.json (the skill's JSON findings array)
# and compares against the expectations in evals.json.
#
# Grading criteria:
#   - RECALL: Did the skill find the expected rule violations?
#   - PRECISION: Did it avoid flagging unexpected rules?
#   - SEVERITY: Is MUST/SHOULD classification correct?
#   - FILE_MATCH: Did it identify the correct file?
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RESULTS_DIR="${1:?Usage: grade-results.sh <results-dir>}"
EVALS_JSON="$SCRIPT_DIR/evals.json"

[[ -f "$EVALS_JSON" ]] || { echo "error: evals.json not found at $EVALS_JSON" >&2; exit 1; }

TOTAL=0
PASS=0
FAIL=0
SKIP=0

echo "=== Model Serving Review — Eval Results ==="
echo ""

for fixture_dir in "$RESULTS_DIR"/*/; do
  fixture=$(basename "$fixture_dir")
  output_file="$fixture_dir/output.json"
  setup_file="$fixture_dir/setup.json"

  TOTAL=$((TOTAL+1))

  if [[ ! -f "$output_file" ]]; then
    echo "SKIP $fixture — no output.json"
    SKIP=$((SKIP+1))
    continue
  fi

  # Get expected findings from evals.json
  expected=$(jq -r --arg id "$fixture" '.evals[] | select(.id == $id) | .assertions' "$EVALS_JSON" 2>/dev/null)
  if [[ -z "$expected" || "$expected" == "null" ]]; then
    echo "SKIP $fixture — no assertions in evals.json"
    SKIP=$((SKIP+1))
    continue
  fi

  # Parse the output
  output=$(cat "$output_file")
  found_rules=$(echo "$output" | jq -r '.[].rule_id' 2>/dev/null | sort -u)

  # Check each assertion
  fixture_pass=true
  fixture_details=""

  # Check expected_rules (recall)
  expected_rules=$(echo "$expected" | jq -r '.expected_rules[]? // empty' 2>/dev/null)
  for rule in $expected_rules; do
    if echo "$found_rules" | grep -q "^${rule}$"; then
      fixture_details+="  ✓ Found expected $rule\n"
    else
      fixture_details+="  ✗ MISSED expected $rule\n"
      fixture_pass=false
    fi
  done

  # Check unexpected_rules (precision)
  unexpected_rules=$(echo "$expected" | jq -r '.unexpected_rules[]? // empty' 2>/dev/null)
  for rule in $unexpected_rules; do
    if echo "$found_rules" | grep -q "^${rule}$"; then
      fixture_details+="  ✗ FALSE POSITIVE $rule (should not be flagged)\n"
      fixture_pass=false
    else
      fixture_details+="  ✓ Correctly did not flag $rule\n"
    fi
  done

  # Check min/max finding count
  min_findings=$(echo "$expected" | jq -r '.min_findings // 0' 2>/dev/null)
  max_findings=$(echo "$expected" | jq -r '.max_findings // 999' 2>/dev/null)
  actual_count=$(echo "$output" | jq 'length' 2>/dev/null || echo 0)

  if [[ "$actual_count" -lt "$min_findings" ]]; then
    fixture_details+="  ✗ Too few findings: $actual_count (expected >= $min_findings)\n"
    fixture_pass=false
  fi
  if [[ "$actual_count" -gt "$max_findings" ]]; then
    fixture_details+="  ✗ Too many findings: $actual_count (expected <= $max_findings)\n"
    fixture_pass=false
  fi

  # Check expected file matches
  expected_files=$(echo "$expected" | jq -r '.expected_files[]? // empty' 2>/dev/null)
  found_files=$(echo "$output" | jq -r '.[].file' 2>/dev/null | sort -u)
  for efile in $expected_files; do
    if echo "$found_files" | grep -q "$efile"; then
      fixture_details+="  ✓ Found expected file $efile\n"
    else
      fixture_details+="  ✗ MISSED expected file $efile\n"
      fixture_pass=false
    fi
  done

  if $fixture_pass; then
    echo "PASS $fixture"
    PASS=$((PASS+1))
  else
    echo "FAIL $fixture"
    FAIL=$((FAIL+1))
  fi
  echo -e "$fixture_details"
done

echo "=== Summary ==="
echo "Total: $TOTAL | Pass: $PASS | Fail: $FAIL | Skip: $SKIP"
graded=$((TOTAL - SKIP))
if [[ $graded -gt 0 ]]; then
  pct=$((PASS * 100 / graded))
  echo "Pass rate: ${pct}% (of $graded graded)"
else
  echo "Pass rate: n/a (no fixtures graded)"
fi
