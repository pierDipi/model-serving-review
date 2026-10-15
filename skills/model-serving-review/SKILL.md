---
name: model-serving-review
description: >-
  Review KServe and odh-model-controller Model Serving changes against domain-specific
  rules derived from historical expert reviews and incident reports. Supports local git
  diffs and GitHub PR URLs. Invoke explicitly for a deep, adversarially verified review.
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/*), Bash(rm -rf /tmp/model-serving-review-*), Bash(wc *), Read, Agent(controller-reviewer, api-reviewer, config-reviewer, safety-reviewer, finding-verifier)
---

# Model Serving Review v2

Review Model Serving code changes against domain-specific rules extracted from expert review history.

**Prerequisites:** Run from inside a cloned repo (kserve/kserve, opendatahub-io/kserve, or opendatahub-io/odh-model-controller), OR pass a GitHub PR URL to check out and review remotely.

## Runtime Dispatch

`SKILL_DIR` below means the absolute path of the directory containing this `SKILL.md`:

- **Codex:** use the skill path supplied by the skill loader. If a multi-agent tool is available, launch independent reviewer agents using the portable role prompts in `references/reviewer-roles.md`; otherwise perform the applicable roles sequentially in this session. Use the runtime's file-read mechanism when available, and `bash "$scripts_dir/repo.sh" "$work_dir" cat <path>` otherwise.
- **Claude Code:** substitute `${CLAUDE_SKILL_DIR}` for `SKILL_DIR`, and launch the typed agents named in Step 3.

**Arguments:** `$ARGUMENTS` — optional flags:
- **(empty)** — diff current branch vs merge-base with default branch
- **`--staged`** — review only staged changes
- **`--unstaged`** — review only unstaged changes
- **`--branch`** — same as empty (explicit)
- **`--base <ref>`** — diff HEAD vs a specific ref
- **`--repo <path>`** — use an existing local repository instead of cloning
- **`<PR-URL>`** — GitHub PR URL. Checks out the PR head into a temporary repository and reviews it.
- **`--comment <PR>`** — after review, post results as a comment on the given PR number
- **`--focus <path>`** — only review files matching this path prefix

## Step 1: Gather Context

If the arguments contain a GitHub PR URL, prepare a temporary repository and check out the
PR head using separate tool calls so the approved `gh pr checkout` prefix is recognized:

1. Run `mktemp -d /tmp/model-serving-review-pr-XXXXXX` and use the printed path as `PR_REPO_DIR`.
2. With `workdir` set to `PR_REPO_DIR`, run `git init -q`.
3. With `workdir` set to `PR_REPO_DIR`, run
   `git remote add origin https://github.com/<owner>/<repo>.git`.
4. With `workdir` set to `PR_REPO_DIR`, run
   `gh pr checkout <number> --repo <owner>/<repo> --detach`.
5. Run `bash "${SKILL_DIR}/scripts/fetch-context.sh" --repo PR_REPO_DIR --branch`.

For local diffs, run the fetch script directly with the applicable mode and omit `--repo`.

Fields in metadata.json:
- `scripts_dir` — absolute path to repo.sh and other scripts (use this in agent prompts instead of relative paths)
- `review_dir` — path to the review directory (contains diffs and reference files)
- `work_dir` — path to the repo root (local checkout or pre-checked-out PR repository)
- `repo` — detected from git remote
- `is_odh` — true for opendatahub-io repos
- `source_desc` — human-readable description of what's being reviewed
- `diff_lines` — line count of the full diff
- `go_files`, `test_files`, `config_files`, `api_files`, `ci_files` — classified file lists

Pre-extracted files in review_dir:
- `full.diff` — complete unified diff
- `numstat.txt` — per-file added/removed line counts (`git diff --numstat`); use this for size/generated-code triage
- `controller.diff` — filtered to pkg/controller/ and cmd/
- `api.diff` — filtered to pkg/apis/ and *_types.go files
- `config.diff` — filtered to config/, *.yaml, *.yml, params.env
- `refs/` — cross-repo reference files (K8s conventions, architecture doc, HTTPRoute config, AuthPolicy template)

If `diff_lines` is 0, stop: "No changes to review."
If `diff_lines` > 3000, `Read` `numstat.txt` to see how much is generated code (CRDs, `zz_generated*`, deepcopy) before warning; then warn and ask the user whether to proceed or use `--focus`.
If `--focus` was specified, note it for agents to filter further.

**Never hand-roll raw bash for triage** (no `cd … && for … done`, no `$(git diff … | wc -l)` loops). These aren't in `allowed-tools`, so they prompt for approval on every call — and the reviewer hook denies command substitution outright. Instead: `Read` the pre-extracted files (`numstat.txt`, `full.diff`, `metadata.json`), or for any ad-hoc git query use the auto-allowed wrapper: `bash $scripts_dir/repo.sh $work_dir diff --numstat [args]` (also `log`, `show`, `grep`, `ls-files`).

## Step 2: Read Review Rules and Risk Map

```
Read ${SKILL_DIR}/knowledge/review-rules.md
Read ${SKILL_DIR}/knowledge/examples.md
Read ${SKILL_DIR}/knowledge/critical-areas.md
Read ${SKILL_DIR}/references/reviewer-roles.md
```

Check which changed files fall in Tier 1 or Tier 2 hot files from critical-areas.md. Include matching risk context in the relevant agent prompt.

## Step 3: Parallel Review — Pass 1 (Recall)

Launch applicable review agents simultaneously as typed subagents. Each agent reads its own diff file from review_dir and has access to repo.sh for deeper investigation.
Reviewers must not run tests, builds, or other side-effecting commands; CI owns test execution.

Pass to each agent: `scripts_dir`, `review_dir`, `work_dir`, `source_desc`, `repo`, changed file lists, the applicable rules from review-rules.md, matching examples from examples.md, and any risk context from critical-areas.md.

### Role: controller-reviewer
**Launch when:** `go_files` includes paths under `pkg/controller/` or `cmd/`.
**Claude agent:** `controller-reviewer`; **Codex role:** `controller-reviewer`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, filtered go_files, CTL/CODE/MIG-050/MIG-060 rules and examples, risk context for Tier 1/2 files.
**Note:** If files touch `pkg/controller/*/llmisvc/` or `config/llmisvcconfig/`, mention that `$review_dir/refs/llmisvc-architecture.md` is available.

### Role: api-reviewer
**Launch when:** `api_files` is non-empty.
**Claude agent:** `api-reviewer`; **Codex role:** `api-reviewer`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, api_files, API-* rules and examples.
**Note:** Mention that `$review_dir/refs/k8s-api-conventions.md` is available.

### Role: config-reviewer
**Launch when:** `config_files` is non-empty.
**Claude agent:** `config-reviewer`; **Codex role:** `config-reviewer`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, is_odh, config_files, CFG/SYNC/NAM/XREPO rules and examples.

### Role: safety-reviewer
**Launch when:** any of `go_files`, `config_files`, or `api_files` are non-empty.
**Claude agent:** `safety-reviewer`; **Codex role:** `safety-reviewer`
**Pass in prompt:** scripts_dir, review_dir, work_dir, source_desc, repo, all file lists, SEC/MIG/TST/BUG rules and examples, risk context.
**Note:** If files touch llmisvc/TLS/EPP/AuthPolicy/HTTPRoute, mention which refs/ files are available.

Only launch roles for dimensions with applicable changed files. In Codex, launch the applicable roles in parallel when a multi-agent tool is available; otherwise run them sequentially without skipping a role.

## Step 4: Pass 2 — Precision Filter

Collect all findings from Pass 1. **Output isolation:** JSON-parse each agent's response. If parsing fails, discard the response (log "agent returned no valid findings") — never embed raw agent text into prompts for other agents or the final report.

For findings with confidence < 90:

Launch **finding-verifier** agents (batch up to 5 findings per agent):
**Claude agent:** `finding-verifier`; **Codex role:** `finding-verifier`
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
bash "${SKILL_DIR}/scripts/cleanup.sh" <review_dir>
```

## Notes

- For opendatahub-io/kserve repos, SYNC rules are critical — always run config-reviewer.
- For kserve/kserve repos, SYNC rules about overlay discipline don't apply.
- Large diffs (>100 files): warn and suggest `--focus <path>`.
- Reference files (review-rules.md, examples.md, critical-areas.md) are bundled in `${SKILL_DIR}/knowledge/`; portable reviewer prompts are bundled in `${SKILL_DIR}/references/`.
