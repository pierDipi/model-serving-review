#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"

# fetch-context.sh — Gathers review context and writes it to a review directory.
# Outputs the path to metadata.json (read it with the Read tool — no jq needed).
# Diffs are written as separate files, not embedded in JSON.

MODE=""
BASE_REF=""
PR_URL=""
WORK_DIR=""
REPO_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged)   MODE="staged"; shift ;;
    --unstaged) MODE="unstaged"; shift ;;
    --branch)   MODE="branch"; shift ;;
    --base)     MODE="base"; BASE_REF="$2"; shift 2 ;;
    --repo)     REPO_PATH="$2"; shift 2 ;;
    https://github.com/*/pull/*)
      PR_URL="$1"; shift ;;
    *)          shift ;;
  esac
done

# Always create a review directory under /tmp
REVIEW_DIR=$(mktemp -d "/tmp/model-serving-review-XXXXXX")

# If a PR URL was given, use the pre-checked-out repository supplied by --repo.
if [[ -n "$PR_URL" ]]; then
  PR_REPO=$(echo "$PR_URL" | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/.*|\1|')
  PR_NUMBER=$(echo "$PR_URL" | sed -E 's|.*/pull/([0-9]+).*|\1|')

  if [[ -n "$REPO_PATH" ]]; then
    WORK_DIR="$REPO_PATH"
  elif [[ -n "${MODEL_SERVING_REVIEW_REPO:-}" ]]; then
    WORK_DIR="$MODEL_SERVING_REVIEW_REPO"
  else
    echo "error: PR URL mode requires --repo <path> pointing to a pre-checked-out PR head" >&2
    exit 2
  fi
  cd "$WORK_DIR"
  MODE="branch"
else
  WORK_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  cd "$WORK_DIR"
fi

detect_repo() {
  local url
  for remote in upstream origin; do
    if url=$(git remote get-url "$remote" 2>/dev/null); then
      break
    fi
  done
  if [[ "$url" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "unknown"
  fi
}

default_branch() {
  local ref
  for remote in upstream origin; do
    ref=$(git symbolic-ref "refs/remotes/${remote}/HEAD" 2>/dev/null || echo "")
    if [[ -n "$ref" ]]; then
      echo "${ref##*/}"
      return
    fi
    for candidate in main master; do
      if git rev-parse --verify "${remote}/${candidate}" &>/dev/null; then
        echo "${remote}/${candidate}"
        return
      fi
    done
  done
  echo "master"
}

REPO=$(detect_repo)
IS_ODH="false"
[[ "$REPO" == *opendatahub* ]] && IS_ODH="true"

LOCAL_BRANCH=$(git branch --show-current 2>/dev/null || echo "HEAD")
DB=$(default_branch)

[[ -z "$MODE" ]] && MODE="branch"

DIFF_ARGS=""
SOURCE_DESC=""

case "$MODE" in
  staged)
    DIFF_ARGS="--cached"
    SOURCE_DESC="staged changes"
    ;;
  unstaged)
    DIFF_ARGS=""
    SOURCE_DESC="unstaged changes"
    ;;
  branch)
    MERGE_BASE=$(git merge-base HEAD "$DB" 2>/dev/null || echo "HEAD~1")
    DIFF_ARGS="${MERGE_BASE}..HEAD"
    SOURCE_DESC="branch ${LOCAL_BRANCH} vs ${DB} ($(git rev-parse --short "${MERGE_BASE}")..$(git rev-parse --short HEAD))"
    ;;
  base)
    DIFF_ARGS="${BASE_REF}..HEAD"
    SOURCE_DESC="HEAD vs ${BASE_REF}"
    ;;
esac

# Get all changed files
if [[ "$MODE" == "unstaged" ]]; then
  FILES=$(git diff --name-only)
elif [[ "$MODE" == "staged" ]]; then
  FILES=$(git diff --cached --name-only)
else
  FILES=$(git diff --name-only $DIFF_ARGS)
fi

# Filter out generated files marked in .gitattributes
if [[ -f .gitattributes ]]; then
  GENERATED_PATTERNS=$(grep -E 'linguist-generated|^[^ ]+ .*generated' .gitattributes | awk '{print $1}' || true)
  if [[ -n "$GENERATED_PATTERNS" ]]; then
    FILTER_FILE=$(mktemp)
    echo "$GENERATED_PATTERNS" > "$FILTER_FILE"
    FILES=$(echo "$FILES" | grep -v -f "$FILTER_FILE" || true)
    rm -f "$FILTER_FILE"
  fi
fi

# Write full diff
if [[ "$MODE" == "unstaged" ]]; then
  git diff > "$REVIEW_DIR/full.diff"
elif [[ "$MODE" == "staged" ]]; then
  git diff --cached > "$REVIEW_DIR/full.diff"
else
  git diff $DIFF_ARGS > "$REVIEW_DIR/full.diff"
fi

DIFF_LINES=$(wc -l < "$REVIEW_DIR/full.diff")

# Per-file added/removed line counts (for triage without ad-hoc bash loops).
if [[ "$MODE" == "unstaged" ]]; then
  git diff --numstat > "$REVIEW_DIR/numstat.txt" 2>/dev/null || true
elif [[ "$MODE" == "staged" ]]; then
  git diff --cached --numstat > "$REVIEW_DIR/numstat.txt" 2>/dev/null || true
else
  git diff $DIFF_ARGS --numstat > "$REVIEW_DIR/numstat.txt" 2>/dev/null || true
fi

# Write per-dimension filtered diffs
if [[ "$MODE" == "unstaged" ]]; then
  git diff -- 'pkg/controller/' 'cmd/' > "$REVIEW_DIR/controller.diff" 2>/dev/null || true
  git diff -- 'pkg/apis/' '*_types.go' '*_types_func.go' '*_lifecycle.go' > "$REVIEW_DIR/api.diff" 2>/dev/null || true
  git diff -- 'config/' '*.yaml' '*.yml' 'params.env' ':!test/' ':!.github/' ':!docs/' > "$REVIEW_DIR/config.diff" 2>/dev/null || true
elif [[ "$MODE" == "staged" ]]; then
  git diff --cached -- 'pkg/controller/' 'cmd/' > "$REVIEW_DIR/controller.diff" 2>/dev/null || true
  git diff --cached -- 'pkg/apis/' '*_types.go' '*_types_func.go' '*_lifecycle.go' > "$REVIEW_DIR/api.diff" 2>/dev/null || true
  git diff --cached -- 'config/' '*.yaml' '*.yml' 'params.env' ':!test/' ':!.github/' ':!docs/' > "$REVIEW_DIR/config.diff" 2>/dev/null || true
else
  git diff $DIFF_ARGS -- 'pkg/controller/' 'cmd/' > "$REVIEW_DIR/controller.diff" 2>/dev/null || true
  git diff $DIFF_ARGS -- 'pkg/apis/' '*_types.go' '*_types_func.go' '*_lifecycle.go' > "$REVIEW_DIR/api.diff" 2>/dev/null || true
  git diff $DIFF_ARGS -- 'config/' '*.yaml' '*.yml' 'params.env' ':!test/' ':!.github/' ':!docs/' > "$REVIEW_DIR/config.diff" 2>/dev/null || true
fi

# Classify files
GO_FILES=$(echo "$FILES" | grep -E '\.go$' | grep -v '_test\.go$' || true)
TEST_FILES=$(echo "$FILES" | grep -E '(_test\.go$|^test/)' || true)
CONFIG_FILES=$(echo "$FILES" | grep -E '(^config/|\.yaml$|\.yml$|kustomization|params\.env)' || true)
API_FILES=$(echo "$FILES" | grep -E '(^pkg/apis/|_types\.go$|_types_func\.go$|_lifecycle\.go$)' || true)
CI_FILES=$(echo "$FILES" | grep -E '(^\.github/|^Makefile$|^hack/)' || true)

# Fetch cross-repo reference files (small static files, always fetched)
mkdir -p "$REVIEW_DIR/refs"
curl -sfL "https://raw.githubusercontent.com/kubernetes/community/refs/heads/main/contributors/devel/sig-architecture/api-conventions.md" \
  > "$REVIEW_DIR/refs/k8s-api-conventions.md" 2>/dev/null || true
curl -sfL "https://raw.githubusercontent.com/opendatahub-io/architecture-context/refs/heads/main/overlays/0011-kserve-llm-d-architecture.md" \
  > "$REVIEW_DIR/refs/llmisvc-architecture.md" 2>/dev/null || true
curl -sfL "https://raw.githubusercontent.com/kserve/kserve/refs/heads/master/config/llmisvcconfig/config-llm-router-route.yaml" \
  > "$REVIEW_DIR/refs/httproute-config.yaml" 2>/dev/null || true
curl -sfL "https://raw.githubusercontent.com/opendatahub-io/odh-model-controller/refs/heads/incubating/internal/controller/resources/template/authpolicy_llm_isvc_userdefined.yaml" \
  > "$REVIEW_DIR/refs/authpolicy-template.yaml" 2>/dev/null || true

# Write metadata JSON (no diff embedded — diffs are separate files)
to_json_array() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "[]"
  else
    echo "$input" | jq -R . | jq -s .
  fi
}

jq -n \
  --arg scripts_dir "$SCRIPTS_DIR" \
  --arg repo "$REPO" \
  --arg is_odh "$IS_ODH" \
  --arg branch "$LOCAL_BRANCH" \
  --arg source_desc "$SOURCE_DESC" \
  --arg work_dir "$WORK_DIR" \
  --arg review_dir "$REVIEW_DIR" \
  --argjson diff_lines "$DIFF_LINES" \
  --argjson files "$(to_json_array "$FILES")" \
  --argjson go_files "$(to_json_array "$GO_FILES")" \
  --argjson test_files "$(to_json_array "$TEST_FILES")" \
  --argjson config_files "$(to_json_array "$CONFIG_FILES")" \
  --argjson api_files "$(to_json_array "$API_FILES")" \
  --argjson ci_files "$(to_json_array "$CI_FILES")" \
  '{
    scripts_dir: $scripts_dir,
    repo: $repo,
    is_odh: ($is_odh == "true"),
    branch: $branch,
    source_desc: $source_desc,
    work_dir: $work_dir,
    review_dir: $review_dir,
    diff_lines: $diff_lines,
    files: $files,
    go_files: $go_files,
    test_files: $test_files,
    config_files: $config_files,
    api_files: $api_files,
    ci_files: $ci_files
  }' > "$REVIEW_DIR/metadata.json"

# Output the path — the orchestrator reads this with the Read tool
echo "$REVIEW_DIR/metadata.json"
