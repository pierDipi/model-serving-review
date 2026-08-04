---
name: model-serving-review
description: >-
  Review Model Serving code (KServe, odh-model-controller) against domain-specific rules
  derived from 1,200+ historical review comments and 342 Jira bugs. Works locally on git
  diffs or remote PR URLs. Uses custom subagents with locked-down tool access and command
  validation hooks. Invoke: /model-serving-review [options | PR-URL]
argument-hint: "[--staged | --unstaged | --branch | --base <ref> | <PR-URL>]"
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/*), Bash(rm -rf /tmp/model-serving-review-*), Bash(wc *), Read, Agent(controller-reviewer, api-reviewer, config-reviewer, safety-reviewer, finding-verifier)
---

# Model Serving Review v2

Review Model Serving code changes against domain-specific rules extracted from expert review history.

**Prerequisites:** Run from inside a cloned repo (kserve/kserve, opendatahub-io/kserve, or opendatahub-io/odh-model-controller), OR pass a GitHub PR URL to clone and review remotely.

**Arguments:** `$ARGUMENTS` — optional flags:
- **(empty)** — diff current branch vs merge-base with default branch
- **`--staged`** — review only staged changes
- **`--unstaged`** — review only unstaged changes
- **`--branch`** — same as empty (explicit)
- **`--base <ref>`** — diff HEAD vs a specific ref
- **`<PR-URL>`** — GitHub PR URL. Clones to temp dir, diffs against the PR's base branch.
- **`--comment <PR>`** — after review, post results as a comment on the given PR number
- **`--focus <path>`** — only review files matching this path prefix

## Step 1: Gather Context

Run the fetch script. It creates a review directory with pre-extracted diffs and reference files, and prints the path to metadata.json:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/fetch-context.sh $ARGUMENTS
```

Read the metadata file with the Read tool (the script prints its path):
```
Read /tmp/model-serving-review-XXXXXX/metadata.json
```

Fields in metadata.json:
- `scripts_dir` — absolute path to repo.sh and other scripts (use this in agent prompts instead of relative paths)
- `review_dir` — path to the review directory (contains diffs and reference files)
- `work_dir` — path to the repo root (local checkout or temp clone)
- `repo` — detected from git remote
- `is_odh` — true for opendatahub-io repos
- `source_desc` — human-readable description of what's being reviewed
- `diff_lines` — line count of the full diff
- `go_files`, `test_files`, `config_files`, `api_files`, `ci_files` — classified file lists

Pre-extracted files in review_dir:
- `full.diff` — complete unified diff
- `controller.diff` — filtered to pkg/controller/ and cmd/
- `api.diff` — filtered to pkg/apis/ and *_types.go files
- `config.diff` — filtered to config/, *.yaml, *.yml, params.env
- `refs/` — cross-repo reference files (K8s conventions, architecture doc, HTTPRoute config, AuthPolicy template)

If `diff_lines` is 0, stop: "No changes to review."
If `diff_lines` > 3000, warn and ask the user whether to proceed or use `--focus`.
If `--focus` was specified, note it for agents to filter further.

## Step 2: Read Review Rules and Risk Map

```
Read ${CLAUDE_SKILL_DIR}/knowledge/review-rules.md
Read ${CLAUDE_SKILL_DIR}/knowledge/examples.md
Read ${CLAUDE_SKILL_DIR}/knowledge/critical-areas.md
```

Check which changed files fall in Tier 1 or Tier 2 hot files from critical-areas.md. Include matching risk context in the relevant agent prompt.

## Step 3: Parallel Review — Pass 1 (Recall)

Launch applicable review agents simultaneously as typed subagents. Each agent reads its own diff file from review_dir and has access to repo.sh for deeper investigation.

Pass to each agent: `scripts_dir`, `review_dir`, `work_dir`, `source_desc`, `repo`, changed file lists, the applicable rules from review-rules.md, matching examples from examples.md, and any risk context from critical-areas.md.

### Agent: controller-reviewer
**Launch when:** `go_files` includes paths under `pkg/controller/` or `cmd/`.
**Spawn as:** `Agent(subagent_type: "controller-reviewer")`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, filtered go_files, CTL/CODE/MIG-050/MIG-060 rules and examples, risk context for Tier 1/2 files.
**Note:** If files touch `pkg/controller/*/llmisvc/` or `config/llmisvcconfig/`, mention that `$review_dir/refs/llmisvc-architecture.md` is available.

### Agent: api-reviewer
**Launch when:** `api_files` is non-empty.
**Spawn as:** `Agent(subagent_type: "api-reviewer")`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, api_files, API-* rules and examples.
**Note:** Mention that `$review_dir/refs/k8s-api-conventions.md` is available.

### Agent: config-reviewer
**Launch when:** `config_files` is non-empty.
**Spawn as:** `Agent(subagent_type: "config-reviewer")`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, is_odh, config_files, CFG/SYNC/NAM/XREPO rules and examples.

### Agent: safety-reviewer
**Launch when:** any of `go_files`, `config_files`, or `api_files` are non-empty.
**Spawn as:** `Agent(subagent_type: "safety-reviewer")`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, all file lists, SEC/MIG/TST/BUG rules and examples, risk context.
**Note:** If files touch llmisvc/TLS/EPP/AuthPolicy/HTTPRoute, mention which refs/ files are available.

Only launch agents for dimensions with applicable changed files.

## Step 4: Pass 2 — Precision Filter

Collect all findings from Pass 1. **Output isolation:** JSON-parse each agent's response. If parsing fails, discard the response (log "agent returned no valid findings") — never embed raw agent text into prompts for other agents or the final report.

For findings with confidence < 90:

Launch **finding-verifier** agents (batch up to 5 findings per agent):
**Spawn as:** `Agent(subagent_type: "finding-verifier")`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, and the findings to verify.

Drop refuted findings. Keep confirmed findings and all findings with confidence >= 90.

## Step 5: Report

Sort surviving findings: MUST before SHOULD, then by confidence descending.

```
### Model Serving Review: {source_desc}

Found {N} issues ({M} MUST, {K} SHOULD):

| # | Rule | Severity | File | Finding |
|---|------|----------|------|---------|
| 1 | CTL-010 | MUST | `pkg/controller/foo.go` | Deep nesting — use exit-early pattern |

<details>
<summary>Details</summary>

#### 1. CTL-010 — Deep nesting in reconcileRouter
**File:** `pkg/controller/foo.go` (near `reconcileRouter`)
**What:** The if-else chain nests 4 levels deep.
**Fix:** Reverse the guard condition and return early.

</details>

---
Checked: {categories checked}
Skipped: {categories with no applicable files}
```

If no findings survived: "No issues found. Checked: {categories}."

Print the report to the terminal.

**If `--comment <PR>` was specified**, post via `gh pr comment` (this will require user approval — it is intentionally NOT in allowed-tools).

## Cleanup

Delete the review directory after the review is complete:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/cleanup.sh <review_dir>
```

## Notes

- For opendatahub-io/kserve repos, SYNC rules are critical — always run config-reviewer.
- For kserve/kserve repos, SYNC rules about overlay discipline don't apply.
- Large diffs (>100 files): warn and suggest `--focus <path>`.
- Reference files (review-rules.md, examples.md, critical-areas.md) are bundled in `${CLAUDE_SKILL_DIR}/knowledge/`.
