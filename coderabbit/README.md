# CodeRabbit configs from the model-serving-review rubric

These `.coderabbit.yaml` configs port the `model-serving-review` skill's rubric
(`skills/model-serving-review/knowledge/review-rules.md` — derived from 1,219 review
comments and 759 Jira bugs) into automated CodeRabbit PR review, so the same rules run
on every pull request without invoking the skill manually.

The skill and CodeRabbit are complementary: the skill does deep, multi-agent,
adversarially-verified review on demand; CodeRabbit gives lightweight always-on coverage
of the file-scoped and PR-level rules.

## What's here

```
coderabbit/
├── opendatahub-io-kserve/      → copy to root of opendatahub-io/kserve
│   ├── .coderabbit.yaml
│   └── .coderabbit/ast-grep/rules/*.yml
└── odh-model-controller/       → copy to root of opendatahub-io/odh-model-controller
    ├── .coderabbit.yaml
    └── .coderabbit/ast-grep/rules/*.yml
```

Two configs, not one: CodeRabbit reads `.coderabbit.yaml` from the **root of the repo
being reviewed**, and the two repos differ in layout (`pkg/controller/**` vs
`internal/controller/**`), rule applicability (SYNC-* overlay discipline is ODH-kserve
only), and ownership (odh-model-controller owns the AuthPolicy templates).

## Deploying

1. Copy the matching directory's contents into the target repo's root:
   ```bash
   cp -r coderabbit/odh-model-controller/. /path/to/odh-model-controller/
   ```
   This lands `.coderabbit.yaml` and `.coderabbit/ast-grep/rules/` at the repo root.
2. Commit both to the repo's **default branch** — CodeRabbit only reads config from the
   default branch.
3. Open a test PR and confirm CodeRabbit picks up the config (it echoes the active
   profile/checks in its review).

## How the rubric maps to CodeRabbit (grounded best practices)

Each rubric rule was routed to the CodeRabbit mechanism that fits its shape, per
CodeRabbit's own guidance (keep rules specific/enforceable, scope to high-traffic paths,
start permissive):

| Mechanism                                                           | Used for                                    | Example rules                                                                      |
|---------------------------------------------------------------------|---------------------------------------------|------------------------------------------------------------------------------------|
| `reviews.path_instructions` (glob-scoped natural-language guidance) | Rules with a clear file-path trigger        | API-* → `pkg/apis/**`, CTL-* → controller dirs, SEC-070 → AuthPolicy templates     |
| `reviews.pre_merge_checks.custom_checks` (PR-level pass/fail)       | Cross-cutting policies not tied to one file | TST-010 (regression tests), CTL-100 (upgrade restart), XREPO-010, SEC-065, BUG-050 |
| `reviews.tools.ast-grep` (structural AST patterns)                  | Precise code shapes                         | SEC-030 `InsecureSkipVerify: true`, CODE-020 `OwnerReferences[0]`                  |

Applied conventions:

- **`profile: chill`** — start conservative to avoid the day-one noise that makes teams
  tune the tool out. Move to `assertive` after 2–4 weeks.
- **`pre_merge_checks` mode is per-check.** The highest-confidence, low-false-positive MUST
  rules are `error` (block merge, with `request_changes_workflow: true`): CTL-100/BUG-010
  upgrade-restart, SEC-065 AuthPolicy/HTTPRoute coverage, and BUG-050 RBAC-for-new-watches
  (odh-model-controller). Judgment-heavy checks that need PR context stay `warning`
  (TST-010, XREPO-010, MIG-050/060) to avoid false-positive blocks. Note: `profile` (kept at
  `chill`) only tunes CodeRabbit's *built-in* commentary — it does not gate these grounded
  checks, which fire at any profile.
- **`path_filters`** exclude generated/vendored code so review budget goes to real changes.
- **Rule IDs are in every instruction** so CodeRabbit's comments cite the rubric and trace
  back to `review-rules.md`.
- CodeRabbit also auto-loads `AGENTS.md` / `CLAUDE.md` as Code Guidelines if present in the
  target repo — these configs layer PR-level enforcement on top of that shared context.

## Not ported (and why)

Some rubric rules need cross-file/cross-repo reasoning or runtime knowledge that a single
per-file review can't reliably do — these stay the skill's job:

- **SYNC-020/030** (sync-vs-cherry-pick, branch targeting) — needs git history/PR target.
- **CTL-020 nil-panic tracing**, **CTL-030 event-on-success** — need dataflow, not a
  pattern match; expressed as `path_instructions` guidance rather than `ast-grep` to avoid
  false positives.
- **BUG-120 storage-initializer** deep failure modes (execve overflow, FIPS binary) — kept
  as path guidance; too runtime-dependent for a pass/fail gate.

Run `/model-serving-review` for the full multi-agent, verified pass.

## Extending

- After a few weeks, comment `@coderabbitai emit path instructions` on a PR to collect
  CodeRabbit's own suggested path instructions from the last 7 days into a PR.
- Add ast-grep rules under `.coderabbit/ast-grep/rules/` (one rule per file, `id` +
  `language` + `rule` + `message`). Validate locally with `ast-grep scan`.
