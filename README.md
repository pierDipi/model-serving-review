# Model Serving Review

Domain-specific code review for [KServe](https://github.com/kserve/kserve)
and [odh-model-controller](https://github.com/opendatahub-io/odh-model-controller), powered by rules extracted from
1,200+ expert review comments and 342 Jira bugs (93 Blocker, 63 Critical).

Works as a Codex skill by default and remains compatible with the Claude Code plugin —
install once, invoke from any KServe checkout.

## What it does

Runs a multi-agent review pipeline on your diff:

1. **Gather context** — extracts diffs, classifies files, fetches cross-repo references
2. **Parallel review** — specialized agents check controller correctness, API consistency, config/overlay discipline,
   and security/migration safety
3. **Adversarial verification** — a verifier agent refutes false positives
4. **Report** — ranked findings with rule IDs, severity, and fix suggestions

Coverage spans 50+ rules across controller patterns, API design, upstream sync, kustomize config, TLS/security,
migration safety, testing, naming, cross-repo coordination, and 14 bug-prone patterns derived from real incidents.

## Always-on review (CodeRabbit)

The same rubric is also ported to [CodeRabbit](https://coderabbit.ai) configs under [`coderabbit/`](coderabbit/), so
the rules run automatically on every PR without invoking the skill. There's a tuned `.coderabbit.yaml` per target repo
(`opendatahub-io/kserve`, `odh-model-controller`) mapping rules to `path_instructions`, `pre_merge_checks`, and
`ast-grep` structural rules. The skill and CodeRabbit are complementary — CodeRabbit gives lightweight always-on
coverage; `$model-serving-review` runs the deep, adversarially-verified pass on demand. See
[`coderabbit/README.md`](coderabbit/README.md) for the rule-to-mechanism mapping and deployment steps.

## Install

### Codex (default)

Install `skills/model-serving-review` as a Codex skill. From a Codex session, ask the
skill installer to install:

```text
<owner>/model-serving-review at skills/model-serving-review
```

For local development, copy or symlink that directory into:

```bash
${CODEX_HOME:-$HOME/.codex}/skills/model-serving-review
```

To enable the current checkout directly, run:

```bash
cd /path/to/model-serving-review
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$PWD/skills/model-serving-review" \
  "${CODEX_HOME:-$HOME/.codex}/skills/model-serving-review"
```

Start a new Codex session after creating the link so the skill is discovered.

### Claude Code

If your team maintains a skills marketplace (e.g., `opendatahub-io/skills-registry`), ask to have this repo added. Then:

```
/plugin install model-serving-review@<marketplace-name>
```

#### As a standalone marketplace

Register this repo directly as a single-plugin marketplace:

```
/plugin marketplace add <owner>/model-serving-review
/plugin install model-serving-review@model-serving-review
```

## Usage

From inside a KServe or odh-model-controller checkout:

Codex:

```text
Use $model-serving-review
```

Claude Code:

```
/model-serving-review
```

### Options

| Flag             | Description                                               |
|------------------|-----------------------------------------------------------|
| *(empty)*        | Diff current branch vs merge-base with default branch     |
| `--staged`       | Review only staged changes                                |
| `--unstaged`     | Review only unstaged changes                              |
| `--branch`       | Same as empty (explicit)                                  |
| `--base <ref>`   | Diff HEAD vs a specific ref                               |
| `--repo <path>`  | Use an existing local repository instead of a remote clone |
| `<PR-URL>`       | GitHub PR URL — checks out into a temporary repository; needs network access |
| `--focus <path>` | Only review files matching this path prefix               |
| `--comment <PR>` | Post results as a PR comment (requires user approval)     |

### Examples

Codex:

```text
# Review current branch
Use $model-serving-review

# Review a remote PR
Use $model-serving-review https://github.com/kserve/kserve/pull/1234

# Review only staged changes
Use $model-serving-review --staged

# Focus on controller code
Use $model-serving-review --focus pkg/controller/
```

Claude Code:

```bash
# Review current branch
/model-serving-review

# Review a remote PR
/model-serving-review https://github.com/kserve/kserve/pull/1234

# Review only staged changes
/model-serving-review --staged

# Focus on controller code
/model-serving-review --focus pkg/controller/
```

## Prerequisites

- Claude Code with plugin support and/or Codex with skill support
- `git`, `jq`, `curl` available in PATH
- `gh` CLI (for PR URL mode and cross-repo lookups)

## Repository structure

```
.claude-plugin/
  marketplace.json              # Plugin manifest — declares skills + agents
agents/
  controller-reviewer.md        # Controller/reconciler correctness
  api-reviewer.md               # API type consistency and K8s conventions
  config-reviewer.md            # Kustomize, overlays, naming
  safety-reviewer.md            # Security, migration, testing, bug patterns
  finding-verifier.md           # Adversarial false-positive filter
skills/
  model-serving-review/
    SKILL.md                    # Orchestrator — drives the review pipeline
    agents/openai.yaml          # Codex UI metadata and explicit-invocation policy
    knowledge/
      review-rules.md           # 50+ review rules with IDs and severity
      examples.md               # Concrete patterns from review history
      critical-areas.md         # Bug-density map for risk-weighted attention
    references/
      reviewer-roles.md         # Portable Codex reviewer and verifier prompts
    scripts/
      fetch-context.sh          # Gathers diffs, classifies files, fetches refs
      repo.sh                   # Sandboxed git/gh operations for agents
      validate-cmd.sh           # PreToolUse hook — command whitelist for agents
      cleanup.sh                # Removes temp review directories
coderabbit/                     # Same rubric ported to CodeRabbit configs (always-on PR review)
  README.md                     # Rule-to-mechanism mapping + deployment
  opendatahub-io-kserve/        # .coderabbit.yaml + ast-grep rules for opendatahub-io/kserve
  odh-model-controller/         # .coderabbit.yaml + ast-grep rules for odh-model-controller
evals/
  evals.json                    # Assertions: expected rules, files, finding counts
  run-evals.sh                  # Sets up synthetic repos from fixtures
  run-skill.sh                  # Runs installed skill with Codex or Claude
  grade-results.sh              # Grades skill output against assertions
  fixtures/
    common.sh                   # Shared helpers (init_repo, write_file, commit)
    ctl-010-deep-nesting.sh     # One fixture per rule or scenario
    ...                         # 36 fixtures total
```

## Local testing

### Validate the Codex skill

```bash
make validate-skill
```

### Test with Codex

Enable the checkout as shown above, start a new Codex session in a KServe checkout, and
invoke:

```text
Use $model-serving-review
```

### Test with Claude Code

From the root of this repo, register a local marketplace:

```
/plugin marketplace add ./
```

This registers the current directory as a marketplace. Claude Code reads `.claude-plugin/marketplace.json` to discover
the plugin.

Install the plugin:

```
/plugin
```

Select **model-serving-review** and install it (user or project scope).

Switch to a KServe checkout with some changes and invoke:

```
/model-serving-review
```

Or test against a specific PR:

```
/model-serving-review https://github.com/kserve/kserve/pull/1234
```

When finished, remove the local marketplace:

```
/plugin marketplace remove model-serving-review
```

### Iterating on changes

After editing skill, agent, or script files:

1. Refresh the installed Codex skill copy and start a new Codex session
2. For Claude Code, reinstall the plugin: `/plugin install model-serving-review@model-serving-review`
3. Start a new conversation (`/clear` or new session) so Claude reloads the updated definitions
4. Run the skill against a known PR to verify

### Verifying the hook sandbox

The `validate-cmd.sh` hook restricts what bash commands agents can run (only `repo.sh` wrapper, `wc`, and safe pipe
targets). To test it:

```bash
# Should allow
echo '{"tool_input":{"command":"bash scripts/repo.sh /tmp/repo diff HEAD~1"}}' | bash skills/model-serving-review/scripts/validate-cmd.sh

# Should deny
echo '{"tool_input":{"command":"rm -rf /"}}' | bash skills/model-serving-review/scripts/validate-cmd.sh
```

## How the rules were built

1. Exported 1,219 review comments from kserve/kserve and opendatahub-io/kserve PRs
2. Exported 759 Jira bugs (156 Blocker/Critical) from RHOAIENG and INFERENG projects
3. Clustered by failure mode and extracted recurring patterns
4. Assigned rule IDs (CTL-*, API-*, CFG-*, SEC-*, MIG-*, TST-*, NAM-*, XREPO-*, BUG-*, CODE-*)
5. Built concrete examples from real review comments
6. Ranked files by bug density to create the risk map

## Evals

The `evals/` directory contains a test harness that measures recall and precision of the review skill against synthetic
repos with planted violations.

### Running evals

```bash
# 1. Set up all fixture repos (or pass specific names)
bash evals/run-evals.sh

# 2. Run the installed skill over every fixture (Codex by default)
RUNTIME=codex bash evals/run-skill.sh $RESULTS_DIR

# Or run with Claude Code
RUNTIME=claude bash evals/run-skill.sh $RESULTS_DIR
```

To invoke one fixture manually from its repo directory, use:

```text
Use $model-serving-review --base HEAD~1
```

For Claude Code:

```bash
cd /tmp/eval-fixture-ctl-010-deep-nesting-XXXXXX
/model-serving-review --base HEAD~1
```

Then grade results with `bash evals/grade-results.sh $RESULTS_DIR`.

### How fixtures work

Each fixture script in `evals/fixtures/` sources `common.sh` and creates a two-commit git repo: an initial clean state,
then a commit introducing the violation under test. The runner calls `fetch-context.sh` to produce a review directory,
then the skill reviews the diff between the two commits.

### Grading criteria

The grader (`grade-results.sh`) checks the skill's JSON output against assertions in `evals.json`:

- **Recall** — did the skill find the expected rule violations?
- **Precision** — did it avoid flagging unexpected rules?
- **File match** — did it identify the correct file?
- **Finding count** — is the count within the expected min/max bounds?

### Eval categories

| Category             | Count | Purpose                                                      |
|----------------------|-------|--------------------------------------------------------------|
| Controller           | 6     | CTL-010 through CTL-100 rule detection                       |
| API                  | 4     | API-010 through API-040 rule detection                       |
| Config               | 5     | CFG, NAM, SYNC, XREPO rule detection                        |
| Security             | 6     | SEC-010 through SEC-075 rule detection                       |
| Bug patterns         | 6     | BUG-020 through BUG-120 rule detection                       |
| Migration            | 2     | MIG-050, MIG-060 rule detection                              |
| Testing              | 3     | TST-010, TST-020, TST-050 rule detection                     |
| Negative (clean)     | 2     | Clean code — should produce zero or near-zero findings       |
| Integration          | 2     | Multi-rule and multi-dimension detection in a single review  |
| Security hardening   | 1     | Prompt injection resistance — injected instructions in diffs |

### Adding a new eval

1. Create a fixture script in `evals/fixtures/<id>.sh` following the pattern in existing fixtures
2. Add a corresponding entry to `evals/evals.json` with `id`, `category`, `description`, and `assertions`
3. Run the fixture to verify it sets up correctly: `bash evals/run-evals.sh <id>`

## Contributing

### Adding a new rule

1. Add the rule to `skills/model-serving-review/knowledge/review-rules.md` with a unique ID and severity
2. Add a concrete example to `skills/model-serving-review/knowledge/examples.md`
3. If the rule applies to a specific subsystem, add it to the relevant agent's "Rules to check" list
4. Test against a PR that should trigger the new rule
5. Keep the CodeRabbit configs in sync: if the rule is file-scoped or a PR-level gate, mirror it into the matching
   `coderabbit/*/.coderabbit.yaml` (`path_instructions` / `pre_merge_checks`, or an `ast-grep` rule for structural
   patterns). `review-rules.md` is the source of truth; the configs are a derived port.

### Modifying an agent

Agent definitions are in `agents/`. Each has:

- **Frontmatter** — name, description, tools, hooks
- **System prompt** — what to check, how to access data, output format

After changes, test by running the full skill against a PR with known issues in that agent's domain.

## License

Apache-2.0
