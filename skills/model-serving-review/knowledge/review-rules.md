# KServe Review Rubric

Rules extracted from 1,219 review comments and 759 Jira bugs (156 Blocker/Critical)
across kserve/kserve and opendatahub-io/kserve.
Each rule has an ID, severity (MUST/SHOULD per RFC 2119), and applicability condition.

## API Design (API-*)

**API-010 | MUST | New or changed API types**
Typed APIs over annotations for first-class features. Annotations lock you into supporting them forever; typed fields
have schema validation and versioning.

**API-020 | MUST | Fields with enum validation**
Avoid strict enum validation when values may grow over time — new methods, new options. Use open enums or string with
documented values.

**API-030 | MUST | New spec fields**
Adding a status condition or spec field is non-breaking. Removing or renaming is breaking. Default to additive changes.

**API-040 | SHOULD | API naming**
Avoid redundant nesting: `speculativeDecoding.speculator` is repetitive. Flatten to `speculator.model`,
`speculator.numTokens`.

**API-050 | SHOULD | New CRD or API version**
Disaggregated serving requires independent scaling of prefill/decode — a top-level `replicas` doesn't work. Validate API
shape against all deployment topologies.

**API-060 | SHOULD | Configuration scope**
Start with top-level configuration that propagates to all managed components. Only add per-component overrides when a
concrete use case requires asymmetric config.

## Controller & Reconciler Patterns (CTL-*)

**CTL-010 | MUST | All reconciler code**
Exit early pattern. Reverse if-conditions to avoid deep nesting: check the negative/exit case first, return, then handle
the main logic at lower indentation.

**CTL-020 | MUST | Code accessing nested spec fields**
Guard against nil panics. Presets/baseRefs mean the "full spec" isn't available until config_merge runs. Fields like
`Router.Scheduler.Pool.Spec.ExtensionRef.Name` can be nil at any level.

**CTL-030 | MUST | Event emission**
Never produce events on success or no-op. This causes high API server load and triggers client-side rate limiting.
Events are for errors and state transitions.

**CTL-040 | MUST | Sub-reconciler handling optional features**
Handle transitions: scheduler enabled→disabled, multi-node→single-node. Generic CRUD must handle `IsNotFound` AND
`meta.IsNoMatchError` (CRD not installed).

**CTL-050 | SHOULD | CRD availability checks**
Remove CRD gating from reconciler setup. Let the controller recover gracefully if CRDs are deployed later — watches
initialize on restart.

**CTL-060 | SHOULD | Repeated logic across sub-reconcilers**
Encapsulate repeated patterns (e.g., `ShouldForceStop`) into shared functions using interfaces like `metav1.Object`.
Don't duplicate branching logic in every reconciler.

**CTL-070 | SHOULD | Scaling/autoscaling reconcilers**
Structure actuator reconciliation for extensibility. Each actuator (HPA, KEDA) should have its own reconcile function
handling its own deletions independently.

**CTL-080 | SHOULD | Status condition updates**
Use non-terminal conditions for observability instead of event floods. Continuous states (scaling status) are
conditions, not events.

**CTL-090 | SHOULD | Reconciler structure**
Have a top-level `finalize(ctx, original)` method for cleanup to prevent the `else` branch from growing organically with
each new component.

**CTL-100 | MUST | Any reconciler output that flows into a Deployment/StatefulSet/LWS pod template**
Controller upgrades must never restart user workloads. The controller reconciles the desired state of Deployments,
StatefulSets, and LWS — any change to the reconciler's output that alters the pod template spec (annotations, labels,
command strings, env vars, volume mounts, security context) changes the pod template hash and triggers a rollout. This
is the #1 source of upgrade Blockers. Every reconciler change must be evaluated with the question: "If the controller
binary is upgraded but the user's CR hasn't changed, will existing pods restart?" Common triggers: (1) shell quoting
changes in modelcar/init container commands (RHOAIENG-71245), (2) annotation injection into pod templates (
RHOAIENG-59339), (3) config value changes that propagate to pod specs (RHOAIENG-59268), (4) security context changes (
readOnlyRootFilesystem, runAsNonRoot), (5) new labels/annotations added to pod metadata, (6) entrypoint script
formatting changes. (26+ Blockers across BUG-010, BUG-030, BUG-120)

## Upstream Sync & ODH Overlay Discipline (SYNC-*)

**SYNC-010 | MUST | opendatahub-io/kserve changes**
Never patch upstream code with inline comments or modifications. Use ODH overlay to remove/patch what's needed.
Modifying base files creates merge conflict debt.

**SYNC-020 | MUST | opendatahub-io/kserve changes**
Prefer sync from upstream/master over cherry-picking individual commits. Cherry-picks diverge history; syncs keep
alignment.

**SYNC-030 | MUST | opendatahub-io/kserve PRs**
Target the correct branch. New features go to master. Release-specific fixes go to the release branch. When odh/master
is synced from upstream, retarget accordingly.

**SYNC-040 | SHOULD | opendatahub-io/kserve additions**
Adding code to upstream-synced files (e.g., code comments, logic) self-sabotages sync for no reason. Decouple
downstream-specific logic into separate files or overlays.

## Kustomize & Configuration (CFG-*)

**CFG-010 | MUST | Accelerator LLMInferenceServiceConfig**
Accelerator configs are overlays on top of base configs in `config/llmisvcconfig/`. They only override the image. Don't
re-set security context, runAsNonRoot, etc. — the base already defines hardening.

**CFG-020 | MUST | Image references in overlays**
Images go in `params.env` and get injected via kustomization. New images need a companion PR in the operator for
injection (see `opendatahub-operator` kserve_support.go).

**CFG-030 | MUST | LLMInferenceServiceConfig changes**
Well-known injected configs live in `config/llmisvcconfig/`. User-provided configs should only override the minimum
delta. Trim configs to the minimum — don't repeat values matching injected defaults.

**CFG-040 | SHOULD | Config versioning**
Embed feature logic in llmisvcconfig base configs where possible. This gives prefix-based stable versioning for free and
prevents container restarts on upgrade.

## Security & TLS (SEC-*)

**SEC-010 | MUST | New sidecar or service that receives traffic from outside its pod**
Include the new service in TLS SANs and IPs of certificates. Check existing workload_tls_self_signed.go for the SAN/IP
builder pattern. Scope: this applies only to containers reachable across the pod boundary (pod-to-pod / Service
traffic). A sidecar that is only reached by other containers in the same pod over loopback (localhost / 127.0.0.1) does
not terminate cross-pod TLS and does not need a cert/SAN — see SEC-075.

**SEC-020 | MUST | New sidecar or service that receives traffic from outside its pod**
Pass TLS flags and volume mounts consistently. Match the pattern in `config-llm-template.yaml` for TLS args, cert paths,
and volume mounts. Same scope as SEC-010: only for containers that receive traffic from outside the pod. Intra-pod
loopback listeners don't need TLS flags/mounts.

**SEC-030 | MUST | Any networking code**
Never use `InsecureSkipVerify`. Gate on certificate rotation support. Check if the target component supports automatic
cert rotation before deciding the TLS strategy.

**SEC-040 | MUST | RBAC changes**
Use ClusterRole for cluster-scoped resources (TokenReview, SubjectAccessReview). Use namespaced Role for
namespace-scoped resources.

**SEC-050 | SHOULD | Security context**
Base configs define runAsNonRoot and security context. Don't re-set in overlays. Check that new containers/pods inherit
the base security context.

**SEC-060 | MUST | AuthPolicy or authorization rules with multiple paths**
Fail closed on authorization path mismatch. When multiple authorization rules exist (e.g., model-level SAR vs
instance-level SAR), a request that carries credentials or headers for a specific auth path (e.g., model routing header)
MUST be explicitly denied if it fails that path's authorization — it must not fall through to a weaker auth path or to
authn-only. The routing signal (header, path prefix) and the authorization check must always agree on which resource is
being accessed. Cross-path fallthrough enables cross-tenant escalation: a request routed to tenant-B's backend via
header but authorized against tenant-A's namespace via path segments. (Discovered
in https://github.com/opendatahub-io/odh-model-controller/pull/881)

**SEC-065 | MUST | AuthPolicy or HTTPRoute changes for LLMInferenceService**
AuthPolicy rules and HTTPRoute paths are a cross-repo security contract. Every routable path/header match must have a
corresponding authorization rule — gaps create unauthenticated access or cross-tenant escalation.
When reviewing **kserve PRs** that change `config/llmisvcconfig/config-llm-router-route.yaml` (new path prefixes, header
matches, catch-all patterns): cross-reference the AuthPolicy template in
odh-model-controller (https://raw.githubusercontent.com/opendatahub-io/odh-model-controller/refs/heads/incubating/internal/controller/resources/template/authpolicy_llm_isvc_userdefined.yaml)
to verify all new routes are covered by auth rules.
When reviewing **odh-model-controller PRs** that change AuthPolicy templates: cross-reference the HTTPRoute template in
kserve (https://raw.githubusercontent.com/kserve/kserve/refs/heads/master/config/llmisvcconfig/config-llm-router-route.yaml)
to verify all routable paths are still authorized or explicitly denied.
(Discovered in https://github.com/opendatahub-io/odh-model-controller/pull/881)

**SEC-070 | MUST | CEL expressions in AuthPolicy templates**
Validate all interpolated values in CEL expressions against injection. Template variables (e.g.,
`{{.ModelRoutingHeader}}`) interpolated into CEL strings must be validated with a strict allowlist before rendering.
Verify the allowlist blocks all CEL-significant characters: quotes, parentheses, backslashes, pipes, ampersands. Add
unit tests covering edge cases for the validation function.

**SEC-075 | MUST | New network connections, HTTP/gRPC clients, or dial targets**
Encrypt traffic that leaves the pod. Any connection to another pod, a Service, or an external endpoint MUST use TLS
(`https://`, gRPC-TLS) — a plaintext `http://` (or insecure dial) to a remote host is a finding. The decisive test is
the destination, not the fact that the connection exists: **traffic that crosses the pod boundary requires TLS;
container-to-container communication within the same pod over loopback (`localhost`, `127.0.0.1`, `::1`) never leaves the
pod's network namespace and MAY be plaintext.** When you see a plaintext connection, resolve the destination host — a
loopback address is acceptable and expected; anything else (a Service name, a peer pod IP/DNS, a routable host) must be
TLS. Don't flag intra-pod loopback calls, and don't wave through remote plaintext just because it "works".
**Exception — user-provided URLs (SHOULD, not MUST):** when the plaintext target is a value the user supplies (a config
field, `storageUri`, CR-provided endpoint) rather than a hardcoded host, downgrade to a warning. Dev/test environments
are legitimate `http://` targets, so accepting user-provided `http://` inputs is fine; the code SHOULD default to TLS,
warn/document when plaintext is used, and never *force* plaintext. Only a hardcoded plaintext remote host is a MUST
finding. This is the counterpart to SEC-010/020 (which cover the server side of the same boundary). (fixture
sec-075-plaintext-http)

## Testing (TST-*)

**TST-010 | MUST | Bug fixes**
Add regression tests. Every fix needs a test that would have caught the bug.

**TST-020 | MUST | Test assertions**
Tests must fail on error, not log warnings on green checks. If a check can't be asserted reliably, document why with
`pytest.mark.xfail`, not a try/except that swallows the failure.

**TST-030 | SHOULD | E2E tests**
Log actions with timestamps for debugging. Collect related objects (pods, pod logs, deployments, InferencePools,
HTTPRoutes) using part-of/component labels — status alone doesn't describe the full picture.

**TST-040 | SHOULD | API version changes**
Augment the test matrix to cover both old and new API versions end-to-end. Don't assume one version — test the migration
path.

**TST-050 | SHOULD | Test skipping**
Guard against skipping critical tests silently. If a prerequisite (RHCL, CRD) is expected to be installed, don't skip —
fail loudly so regressions are noticed.

**TST-060 | SHOULD | Integration tests**
Add integration tests in `*_int_test.go` for controller logic. Smoke E2E tests for new features when resource
requirements allow.

## Naming & Resource Conventions (NAM-*)

**NAM-010 | MUST | New Kubernetes resources**
Prefix with `kserve-` to avoid clashes with other resources in shared namespaces (e.g., `kserve-llm-isvc-vllm-engine`,
not `llm-vllm-engine`).

**NAM-020 | MUST | Webhook names**
Keep webhook names stable across versions. Changing webhook names creates "ghost" webhooks during upgrades (old name
persists without match policy, new name gets created).

**NAM-030 | SHOULD | Naming specificity**
Be specific: `llm-isvc` not just `llm`. Consistency with relabelings and other resources in the namespace.

## Migration & Upgrade Safety (MIG-*)

**MIG-010 | MUST | Changes to propagated labels/annotations**
Top-level `.metadata` label/annotation propagation causes unintended restarts/rollouts when unrelated labels change.
Keep propagation scoped to explicit workload-level labels.

**MIG-020 | MUST | Protocol or API version changes**
Can't assume all services run the latest version. Check the component version (similar to scheduler migration logic) and
fall back to the previous version if the new one can't be determined.

**MIG-030 | MUST | InferencePool or resource migration**
Test migration with actual gateway/proxy versions. An InferencePool migrated to v1 will break if the Istio version
doesn't support it.

**MIG-040 | SHOULD | Feature reconciliation**
Embed feature logic in llmisvcconfig (versioned via prefix) rather than controller code to prevent restarts on upgrade.
Controller changes require pod restarts; config changes don't.

**MIG-050 | MUST | Changes to Go template functions in ReplaceVariables (config_merge.go)**
Template functions registered in `ReplaceVariables` are a shipped API contract. Previously released llmisvcconfig YAML
files reference these functions by name — removing or renaming a function breaks all existing configs on upgrade.
Functions can only be added, never removed or renamed. If a function's behavior needs to change, the new behavior must
be backward-compatible or a new function must be added alongside the old one. The same applies to function signatures —
changing parameter types or count breaks existing template invocations. (kserve/kserve#5717)

**MIG-060 | MUST | Changes to llmisvcconfig template variables or structure**
LLMInferenceServiceConfig templates are versioned by prefix and shipped with releases. Any change to the template
variable names, Go template syntax, or expected input structure breaks previously shipped configs on upgrade. New
variables can be added (templates ignore undefined variables with `{{if}}`), but existing variables cannot be removed or
change type. Test template rendering against configs from the previous release.

## Cross-Repo Coordination (XREPO-*)

**XREPO-010 | MUST | New images or config changes**
Flag when a PR needs companion changes in other repos (operator, odh-model-controller, kserve-module). Missing
coordination blocks deployment.

**XREPO-020 | SHOULD | Module integration**
New overlays or resources must be integrated with the operator module (kserve-module) to be applied. Resources in
overlays that aren't wired into the module won't be deployed.

## Bug-Prone Patterns (BUG-*)

Rules derived from 342 real bugs (93 Blocker, 63 Critical, 75 Major, 65 Normal).

**BUG-010 | MUST | Any change to pod template, annotations, labels, or config**
Upgrade restart risk. See CTL-100 for the core rule. This bug pattern captures the downstream symptoms: unnecessary
rollouts during upgrades caused by annotation injection, shell quoting changes, config value drift, or security context
modifications. The test is: "Does `kubectl diff` on a Deployment managed by this controller show changes when only the
controller binary was upgraded?" (9 Blockers: RHOAIENG-59339, RHOAIENG-59268, RHOAIENG-71245)

**BUG-020 | MUST | Image references in params.env, kustomization, or llmisvcconfig**
Wrong image tag. Placeholder images (`controller:latest`), missing kustomize replacements, and version-mismatched image
tags are a top source of Blockers. Every image reference must have a corresponding kustomize replacement entry AND
operator injection. (10 bugs: RHOAIENG-69531, RHOAIENG-55878, RHOAIENG-75982)

**BUG-030 | MUST | Security context changes (readOnlyRootFilesystem, runAsNonRoot, seccomp)**
Security context breaks GPU/device injection. `readOnlyRootFilesystem: true` breaks CDI-based GPU injection (
nvidia-cdi-hook) and OCI modelcar serving. `runAsNonRoot` breaks procfs symlinks and some xKS deployments. Validate
against all accelerator types and deployment targets. (5 Blockers: RHOAIENG-75488, RHOAIENG-71150, RHOAIENG-56701)

**BUG-040 | MUST | API version bumps, CRD changes, or controller upgrades**
Missing migration logic. Version upgrades without migration logic cause CrashLoopBackOff, deadlocks, and Ready=False.
Every version change needs: migration path, conversion webhook if needed, fallback to previous version. (11 bugs, 7
Blockers: RHOAIENG-58364, RHOAIENG-54344, RHOAIENG-76305)

**BUG-050 | MUST | New CRD watches, new resources, or new API group access**
Missing RBAC. New watches on resources (InferenceModelRewrites, ClusterStorageContainers) need corresponding RBAC
entries in the distro ClusterRole. Aggregated roles need labels for user-facing CRDs. (26 bugs: RHOAIENG-56779,
RHOAIENG-54987, RHOAIENG-60685)

**BUG-060 | MUST | New binaries, sidecars, or Go dependencies on FIPS/restricted clusters**
TLS/FIPS compatibility. New binaries must pass FIPS selftest. Go binaries need FIPS-compliant crypto. Sidecars need
correct OpenSSL initialization. CPU-specific instructions (SIGILL on AMD EPYC). Flag mismatches (`-enable-cert-reload`
not defined). (47 bugs: RHOAIENG-58354, RHOAIENG-58765, INFERENG-6224)

**BUG-070 | MUST | ServiceMonitor, PodMonitor, or metrics port changes**
Monitoring breakage. Hardcoded `matchNamespace` fields, missing NetworkPolicy ports for Prometheus scraping, wrong label
selectors on monitors. Every new metrics endpoint needs: ServiceMonitor/PodMonitor, NetworkPolicy egress rule, and
dashboard integration. (45 bugs: RHOAIENG-59920, INFERENG-5614, INFERENG-6140)

**BUG-080 | SHOULD | Hardcoded timeouts, ports, namespaces, or resource names**
Hardcoded values break at scale or in non-standard environments. Hardcoded startupProbe timeouts fail for large models.
Hardcoded namespace selectors fail in multi-tenant. Hardcoded secrets are security risks. Make values configurable or
derive from context. (8 bugs: RHOAIENG-75793, INFERENG-5614, RHOAIENG-69776)

**BUG-090 | SHOULD | NetworkPolicy changes or new service ports**
NetworkPolicy blocks. New service ports (metrics, webhooks, sidecars) need corresponding NetworkPolicy rules. Prometheus
scraping is frequently blocked by namespace-scoped NetworkPolicies. (8 bugs: RHOAIENG-58209, INFERENG-7687)

**BUG-100 | SHOULD | Kustomize replacement targets or overlay field paths**
Kustomize replacement failures. Targeting non-existent fields (`spec.namespaceSelector.matchNames.0`) breaks the entire
kustomize build. Test replacement paths against the actual manifests. Missing replacements leave placeholder values in
production. (5 bugs: RHOAIENG-56264, RHOAIENG-55878)

**BUG-110 | SHOULD | Multi-node, P/D, or LeaderWorkerSet changes**
Multi-node edge cases. Status conditions stuck at Unknown despite pods running, entrypoint scripts that only consider
the first NIC/HCA, metrics over-counted when LWS replicas have multiple metric-emitting pods. Test with actual
multi-node topologies. (21 bugs: RHOAIENG-70416, INFERENG-6968, INFERENG-8439)

**BUG-120 | MUST | Storage initializer, modelcar container, init container injection, or storageUri handling**
Storage/model injection pipeline failures. Changes to `pkg/utils/storage.go`, modelcar command generation, init
container construction, or webhook storageUri mutation. Distinct from CTL-100 (restart-on-upgrade), this covers
storage-specific breakage: (1) argument list too long — large model lists exceed execve limits (RHOAIENG-30376,
Blocker); (2) HF_TOKEN and credentials not propagated to init containers (RHOAIENG-69344); (3) mutating webhook strips
storageUri when imagePullSecrets secret is deleted (RHOAIENG-61105); (4) FIPS check-payload failure in
storage-initializer binary (RHOAIENG-60931, Blocker); (5) multi-arch build failures for ppc64le/s390x (RHOAIENG-50492,
RHOAIENG-50322, Blockers); (6) versioned model path handling — can't download specific model versions (
RHOAIENG-34931); (7) ClusterStorageContainer manifest doesn't support multi-model download (RHOAIENG-57629); (8)
downloads entire HF repo instead of required files (RHOAIENG-69346). For pod template hash stability of shell quoting
and command strings, see CTL-100. (26 bugs, 9 Blockers)

## Code Quality (CODE-*)

**CODE-010 | SHOULD | Complex init scripts**
Prefer readability over DRY for init/entrypoint scripts. Overly templated bash scripts (gotemplate in bash) are hard to
debug. Push back if readability suffers.

**CODE-020 | SHOULD | Owner references**
Don't assume the first owner reference is "ours". Loop through owner refs and check by kind/name. Guard array access
with length checks.

**CODE-030 | SHOULD | Sidecar configuration**
Use the llmisvcconfig mechanism (well-known configs with prefix versioning) for sidecar injection rather than arbitrary
injection. This gives consistent UX and prevents restart-on-upgrade.

**CODE-040 | SHOULD | Default configuration**
Modify default configurations in the known location rather than injecting overrides arbitrarily. If there will ever be a
better alternative, arbitrary injection locks you in with no override path.
