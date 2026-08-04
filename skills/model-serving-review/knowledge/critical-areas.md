# KServe Critical Areas

Bug-density map extracted from 342 real Jira bugs (93 Blocker, 63 Critical, 75 Major, 65 Normal).
Use this to weight review attention: changes touching high-risk areas deserve deeper scrutiny.

## Risk-Ranked Subsystems

Ranked by severity-weighted score (Blocker×4, Critical×3, Major×2, Normal×1).

| Rank | Subsystem                              | Bugs | Blk | Crt | Maj | Nrm | Blk% |
|------|----------------------------------------|------|-----|-----|-----|-----|------|
| 1    | LLMInferenceService / llm-d controller | 87   | 31  | 22  | 14  | 9   | 36%  |
| 2    | InferenceService core                  | 74   | 24  | 11  | 23  | 9   | 32%  |
| 3    | Deployment / Pod lifecycle             | 75   | 19  | 15  | 14  | 15  | 25%  |
| 4    | Controller / Reconciler                | 52   | 17  | 5   | 12  | 10  | 33%  |
| 5    | RBAC / Auth                            | 44   | 10  | 12  | 9   | 6   | 23%  |
| 6    | Networking / Route / Gateway           | 38   | 7   | 2   | 11  | 10  | 18%  |
| 7    | Monitoring / Metrics                   | 28   | 7   | 4   | 7   | 9   | 25%  |
| 8    | Storage / S3 / PVC                     | 21   | 8   | 3   | 4   | 2   | 38%  |
| 9    | Upgrade / Migration                    | 15   | 10  | 2   | 2   | 0   | 67%  |
| 10   | TLS / Certificates                     | 18   | 3   | 4   | 2   | 7   | 17%  |
| 11   | Webhook / Admission                    | 15   | 5   | 1   | 5   | 2   | 33%  |
| 12   | Config / Overlays / Image Tags         | 11   | 5   | 1   | 1   | 1   | 45%  |

## Hot Files — When You See a Change Here, Dig Deeper

### Tier 1: Highest Bug Concentration

| Path/Pattern                                                      | Dominant Failure Mode                                                                         |
|-------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `config/overlays/odh/` (entire dir)                               | Missing kustomize replacements, placeholder images not substituted, RBAC overlay gaps         |
| `config/overlays/odh/rbac/`                                       | Missing ClusterRole permissions block reconciliation of new CRDs                              |
| `config/overlays/odh/params.env`                                  | Wrong release version tags, missing entries for new images                                    |
| `internal/controller/serving/inferenceservice_controller.go`      | Nil pointer panics, reconcile loops, missing CRD watchers                                     |
| `internal/controller/serving/inferencegraph_controller.go`        | Auth cleanup timeouts, dangling ConfigMap volumes                                             |
| `internal/controller/resources/authpolicy.go`                     | AuthPolicy targeting deleted HTTPRoute, reconcile-on-stop failures                            |
| `pkg/controller/v1beta1/inferenceservice/reconcilers/deployment/` | OCP-specific deployment logic breaks on upgrade, annotation injection                         |
| `pkg/controller/*/llmisvc/workload_tls_self_signed.go`            | TLS cert generation fails in FIPS mode                                                        |
| `pkg/utils/storage.go` / storage initializer                      | HF_TOKEN not propagated, argument list overflow, versioned model download failures (13+ bugs) |
| `config/overlays/odh-modelcache/localmodel-scc.yaml`              | SELinux MCS mismatch, read-only filesystem on model cache nodes                               |

### Tier 2: Significant Bug Source

| Path/Pattern                                                    | Dominant Failure Mode                                                |
|-----------------------------------------------------------------|----------------------------------------------------------------------|
| `config/rbac/role.yaml` / `config/rbac/cluster-scope/role.yaml` | Overly permissive RBAC, missing permissions for new CRDs             |
| `config/rbac/llmisvc/role.yaml`                                 | LLMISVC-specific RBAC gaps                                           |
| `config/llmisvcconfig/config-llm-prefill-template.yaml`         | Schema breaking changes, stale image references                      |
| `config/llmisvcconfig/` (entire dir)                            | Pod template hash changes on upgrade, security context conflicts     |
| `config/webhook/llmisvc/service.yaml`                           | Missing webhook certs, stale configurations after upgrade            |
| `config/internal/base/deployment.yaml`                          | Placeholder `controller:latest` not replaced by kustomize            |
| `cmd/*/main.go`                                                 | Removed flags still referenced in config templates, startup crashes  |
| `cmd/router/main.go` / `cmd/kueue/main.go`                      | Flag incompatibilities between versions, TLS arg errors              |
| `internal/webhook/core/v1/tier_configmap_webhook.go`            | ConfigMap validation errors                                          |
| `internal/controller/utils/nim.go`                              | NIM model name mismatches, ConfigMap 1MB size limit exceeded         |
| `pkg/mmesh/etcd_secret.go`                                      | etcd root credentials leaked to tenant namespaces                    |
| `Dockerfile*` / `Dockerfile.konflux`                            | CGO not enabled for FIPS, multi-arch build failures (ppc64le, s390x) |

## Cross-Cutting Failure Modes

### No Restart on Controller Upgrade (CTL-100) — #1 Blocker Source

Controller upgrades must never restart user workloads. Any reconciler output change that alters the pod template spec (
annotations, labels, command strings, env vars, volume mounts, security context) changes the pod template hash and
triggers a rollout. Common triggers: shell quoting changes in modelcar commands, annotation injection into pod
templates, security context additions, config value drift. The test: "If only the controller binary changes, does
`kubectl diff` show changes on any managed Deployment?"

### Storage Initializer / Modelcar (BUG-120) — 26 bugs, 9 Blockers

The storage-initializer and modelcar injection pipeline is a top-3 bug source. Distinct failure modes: argument list
overflow (execve limits), credential non-propagation (HF_TOKEN), webhook storageUri stripping, FIPS binary failures,
multi-arch build breaks, versioned model path handling.
Key files: `pkg/utils/storage.go`, init container construction, webhook storageUri mutation.

### Upgrade Path (52 bugs, 26 Blockers — largest single failure mode)

Spans: CRD schemas, webhook validation, CLI flags, annotation formats, LLMInferenceServiceConfig presets.
**Signal:** Any change to these areas needs backward-compatibility review. Ask: "What happens to a cluster running the
previous version during a rolling upgrade?"

### FIPS + TLS (~35 bugs)

Go binaries without CGO cannot use FIPS crypto. Static linking blocks OpenSSL. Self-signed cert generation may use
non-FIPS algorithms.
**Signal:** Any change to Dockerfiles, TLS cert generation, or HTTP client construction — verify FIPS compliance.

### Controller Startup Crashes (25 CrashLoopBackOff bugs)

Top patterns: flag definition mismatch (5), FIPS/crypto init failure (4), missing CRD/webhook ordering (3), OOM from
unfiltered informers (3).
**Signal:** Changes to CLI flags, informer filters, or startup ordering need upgrade-path testing.

### Config/Overlay Drift (11 bugs, 45% Blockers — highest Blocker density)

Placeholder images not substituted, params.env referencing wrong versions, ConfigMap name changes not propagated.
**Signal:** Any new deployment or ConfigMap in `config/` must have kustomize replacement entries in ALL overlay
directories.

## llm-d Subcomponent Breakdown (87 bugs)

| Subarea                   | Bugs | Blk | Key Failure Mode                                                      |
|---------------------------|------|-----|-----------------------------------------------------------------------|
| Config / Image References | 40   | 14  | Wrong vLLM image version, readOnlyRootFilesystem breaking CDI         |
| Scheduler / EPP           | 30   | 14  | Image tag not found, missing plugin registration, flag errors         |
| Router / Routing Sidecar  | 26   | 10  | FIPS OpenSSL crash, session-stickiness issues, flag incompatibilities |
| Controller / CRD          | 26   | 11  | Conversion webhook deadlock, CRD validation failures                  |
| Monitoring / Metrics      | 21   | 5   | ServiceMonitor hardcoded namespace, WVA scraping failures             |
| KV Cache / Prefix Cache   | 19   | 9   | SIGILL on older CPUs, FIPS selftest, scorer config schema             |
| WVA / Autoscaling         | 15   | 5   | ConfigMap rename breaks, saturation metric missing                    |

## Label-Based Risk Signals

| Label               | Count | Blk | Signal                                                                          |
|---------------------|-------|-----|---------------------------------------------------------------------------------|
| `cypress_found_bug` | 13    | 11  | UI-discovered bugs are 85% Blockers — late-breaking deployment issues           |
| `FailedQA`          | 7     | 3   | Escaped to QA: controller CrashLoops, reconcile loops, image mismatches         |
| `found_in_nightly`  | 5     | 4   | Nightly breakers: missing RBAC, kustomize errors, CRD incompatibility           |
| `RC1`               | 6     | 4   | Release-candidate regressions: storage-initializer overflow, ModelMesh failures |
| `ProjectGlasswing`  | 10    | 0   | Security: path traversal, pickle deser, cross-tenant storage, RBAC over-grant   |
