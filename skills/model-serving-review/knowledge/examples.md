# KServe Review Examples

Concrete patterns from actual review history. Each example shows the trigger, what to flag, and a representative
comment.

## Controller Patterns

### Exit Early (CTL-010)

```go
// BAD: deep nesting
if !llmSvc.DeletionTimestamp.IsZero() {
    if condition {
        // deeply nested logic
    }
} else {
    // main logic
}

// GOOD: exit early
if !llmSvc.DeletionTimestamp.IsZero() {
    return r.reconcileFinalization(ctx, llmSvc)
}
// main logic at low indentation
```

> "I would make this `if` reversed to not have the deeper nesting and follow the exit early pattern"

### Nil Guard on Nested Specs (CTL-020)

```go
// BAD: assumes all fields are non-nil
name := llmSvc.Spec.Router.Scheduler.Pool.Spec.ExtensionRef.Name

// GOOD: guard each level
if llmSvc.Spec.Router == nil || llmSvc.Spec.Router.Scheduler == nil ||
   llmSvc.Spec.Router.Scheduler.Pool.HasRef() {
    // handle default/fallback
}
```

> "This function is also used to handle transitions from 'scheduler enabled' to 'scheduler disabled', where any of these
> fields can be nil and we need to guard it"

### No Events on Success (CTL-030)

```go
// BAD: event on every successful reconcile
r.Recorder.Event(obj, corev1.EventTypeNormal, "Reconciled", "Successfully reconciled")

// GOOD: only on state transitions or errors
if err != nil {
    r.Recorder.Event(obj, corev1.EventTypeWarning, "ReconcileFailed", err.Error())
}
```

> "Producing an event on success (but also on no-op) can cause a high load on the API server and trigger client-side
> rate limiting. A non-error doesn't mean the object is ready, so the message might be misleading."

### Handle CRD Not Installed (CTL-040)

```go
// BAD: only checks NotFound
if apierrors.IsNotFound(err) {
    return nil
}

// GOOD: also handles CRD not installed
if !apierrors.IsNotFound(err) && !meta.IsNoMatchError(err) {
    return err
}
```

> "Generic CRUD functions handle IsNotFound and IsNoMatchError (IsNoMatchError == LWS is not installed)"

### Extensible Actuator Pattern (CTL-070)

```go
// BAD: monolithic scaling reconciliation
func reconcileScaling(ctx context.Context, ...) error {
    if scaling.WVA != nil {
        if scaling.WVA.HPA != nil { /* HPA logic */ }
        if scaling.WVA.KEDA != nil { /* KEDA logic */ }
    }
}

// GOOD: each actuator handles its own lifecycle
func reconcileActuator(...) {
    reconcileHPA(...)
    reconcileKEDAScaledObject(...)
}

func reconcileHPA(...) {
    if scaling == nil || scaling.WVA == nil || scaling.WVA.HPA == nil {
        Delete(...)
        return
    }
    // reconcile HPA
}
```

> "The logic assumes 2 actuators. Structure it in a way that is extensible, with individual functions handling deletions
> of their own objects."

## Status Conditions

### Subcondition Aggregation (CTL-080)

```go
// BAD: directly set RouterReady from one check
status.MarkTrue(RouterReady)

// GOOD: subconditions aggregate to parent
// GatewaysReady → RouterReady
// InferencePoolReady → RouterReady
status.MarkTrue(GatewaysReady)
// RouterReady is computed from subconditions
```

> "I'd add a 'GatewaysReady' condition and a separate 'DetermineRouterReadiness'. Adding a condition is non-breaking but
> removing is breaking — since we're unsure, leave the single condition for now."

### Continuous State = Condition, Not Event (CTL-080)

```go
// BAD: emit events for ongoing scaling state
r.Recorder.Event(obj, "Normal", "Scaling", "Currently scaling up")

// GOOD: use a non-terminal status condition
status.SetCondition(ScalingActive, metav1.ConditionTrue, "ScalingUp", msg)
```

> "These are continuous states rather than point-in-time occurrences. Using events could cause an event flood. Use
> non-terminal conditions purely for observability."

### No Restart on Controller Upgrade (CTL-100)

```go
// BAD: unconditional shell quoting changes the command string across versions
// v3.4: "mkdir -p '/mnt/models' && ln -sf ..."
// v3.5: "mkdir -p /mnt/models && ln -sf ..."
// → different string → different pod template hash → pod restart on upgrade
func shellQuote(s string) string {
    return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// GOOD: conditional quoting preserves existing command strings (kserve/kserve#5780)
func ShellQuote(s string) string {
    if isShellSafe(s) { return s }
    return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}
```

```go
// BAD: injecting a new annotation into the pod template during reconcile
// Existing pods get a new template hash → rollout
podTemplate.Annotations["serving.kserve.io/deployment-mode"] = "RawDeployment"

// GOOD: annotations that don't affect runtime go on the Deployment metadata,
// NOT the pod template. Or: ensure the annotation was always present.
deployment.Annotations["serving.kserve.io/deployment-mode"] = "RawDeployment"
```

```go
// BAD: changing default security context in reconciler output
// v3.4 didn't set readOnlyRootFilesystem, v3.5 sets it to true
// → different pod template → restart
container.SecurityContext.ReadOnlyRootFilesystem = ptr.To(true)

// GOOD: if adding security hardening, only apply to NEW deployments
// or make it a versioned config in llmisvcconfig so users control the rollout
```

> "We've run into different restart/rollout issues because of unrelated annotations/labels get added."
> The test: "If only the controller binary changes, does `kubectl diff` show changes on any managed Deployment?"

## Upstream Sync

### Don't Modify Upstream Files (SYNC-010)

```yaml
# BAD: adding comments to upstream kustomization.yaml
# ODH-SPECIFIC: removed component X
resources:
  - ...

# GOOD: use odh overlay to exclude/patch
# config/overlays/odh/kustomization.yaml
patchesStrategicMerge:
  - remove-component-x.yaml
```

> "We will generally have an easier time dealing with conflicts if we don't patch upstream code with code comments and
> instead have odh overlay remove/patch what's not needed."

### Sync Over Cherry-Pick (SYNC-020)

> "Instead of cherry picking a specific commit to master, can we do a sync from kserve/master so that the history is
> aligned? Moving forward that should be the flow."

## Security & TLS

### TLS for New Services (SEC-010, SEC-020)

```yaml
# When adding a new sidecar (e.g., tokenizer), MUST:
# 1. Add service DNS to certificate SANs
# 2. Pass TLS flags matching the main workload pattern
# 3. Mount cert volumes

# Reference patterns in:
# - workload_tls_self_signed.go (SAN builder)
# - config-llm-template.yaml (TLS args + volume mounts)
```

> "We need to include the tokenizer in SANs and IPs of the certificate too... we need to pass TLS flags when enabled (+
> volume mount similar to the main workload)"

### No InsecureSkipVerify (SEC-030)

> "Routing sidecar supports certificate rotation, it's automatic. I'm wondering if we want to annotate our configs and
> gate on that here."

### Plaintext Only Inside the Pod (SEC-075)

```go
// MUST: plaintext to a remote host (Service/peer pod/external) — flag, require TLS
resp, _ := client.Get(fmt.Sprintf("http://%s/metrics", m.endpoint))

// FINE: container-to-container within the same pod over loopback — do not flag
resp, _ := client.Get("http://127.0.0.1:9090/metrics")

// SHOULD (warning): user-provided URL that may be http:// — dev targets are valid.
// Default to TLS, warn when plaintext, but don't reject the user's http:// input.
endpoint := isvc.Spec.Predictor.CustomEndpoint // user-supplied
```

> Traffic crossing the pod boundary requires TLS. Loopback (localhost/127.0.0.1/::1) never leaves the pod and may be
> plaintext. A user-supplied `http://` URL is a warning, not a hard finding — dev/test environments are legitimate
> plaintext targets.

### Authorization Path Mismatch (SEC-060)

```yaml
# BAD: request with model routing header falls through to instance-level SAR
# Routing: header sends request to tenant-B's Service
# Auth: inference-access checks path /{tenant-A-ns}/{tenant-A-name} → SAR passes → cross-tenant access
inference-access:
  when:
    - predicate: "!request.path.startsWith('/v1/')"
    # Missing: no guard against model routing header being present
    # A request with both path segments AND model header uses the wrong auth path

# GOOD: explicitly deny when model routing header is present but model-access-path didn't fire
# Fail closed: the routing signal (header) and auth check (path) must agree
model-routing-deny:
  when:
    - predicate: >-
        '{{.ModelRoutingHeader}}' in request.headers
        && request.headers['{{.ModelRoutingHeader}}'].matches('^publishers/[^/]+/models/.+$')
    - predicate: >-
        !auth.identity.resolvedPath.matches('^/publishers/[^/]+/models/')
  response:
    unauthorized:
      message: "model routing header present but model authorization failed"
```

> The routing signal (header, path prefix) and the authorization check must always agree on which resource is being
> accessed. Cross-path fallthrough enables cross-tenant escalation.
> Discovered in https://github.com/opendatahub-io/odh-model-controller/pull/881

### CEL Injection Prevention (SEC-070)

```go
// BAD: no validation of interpolated value
template := `request.headers['{{.ModelRoutingHeader}}']`
// If ModelRoutingHeader = "x']); malicious_cel(request.headers['y"
// → request.headers['x']); malicious_cel(request.headers['y']

// GOOD: strict allowlist before interpolation
func isValidHTTPHeaderName(name string) bool {
    return regexp.MustCompile(`^[a-z0-9][a-z0-9\-_]*$`).MatchString(name)
}
// + unit tests for: empty string, uppercase, dots, quotes, backslashes,
//   parentheses, pipes, ampersands, multi-byte Unicode
```

## Migration Safety

### Webhook Name Stability (MIG-020, NAM-020)

```yaml
# BAD: renaming webhook during version bump
name: llminferenceservice-v1alpha2.kserve-webhook-server.validator

# GOOD: keep existing name, add new version as separate webhook
# Old name continues to work during rolling upgrade
```

> "By changing the name, an existing installation when upgrading will continue to have the old webhook as a 'ghost'
> without match policy set."

### Version-Aware Fallback (MIG-020)

```go
// BAD: assume latest API version is available
pool := r.createInferencePoolV1(ctx, svc)

// GOOD: check version support, fallback
if r.InferencePoolV1Available {
    pool = r.createInferencePoolV1(ctx, svc)
} else {
    pool = r.createInferencePoolV1Alpha2(ctx, svc)
}
```

> "We cannot do this as there might be services running with older releases. Check what's the scheduler version and
> fallback to previous version if it cannot be determined."

### Label Propagation Restarts (MIG-010)

> "We've run into different restart/rollout issues because of unrelated annotations/labels get added. Keeping the list
> of disallowed up to date is very difficult."

### Template Function Contract (MIG-050)

```go
// BAD: removing or renaming existing template functions (kserve/kserve#5717)
// Previously shipped llmisvcconfig files call these by name — removing breaks upgrade
t, err := template.New("config").
    Funcs(map[string]any{
-       "kvTransferConfig": func(spec any) string { ... },  // REMOVED — breaks shipped configs
-       "shutdownTimeout":  func(spec any, preStop int64) int64 { ... },  // RENAMED — breaks shipped configs
+       "shutdownTimeoutScript": func(spec any, preStop int64) string { ... },  // new name, old one gone
    })

// GOOD: add new functions, keep old ones
t, err := template.New("config").
    Funcs(map[string]any{
        "kvTransferConfig":      func(spec any) string { ... },       // KEPT — shipped configs use it
        "shutdownTimeout":       func(spec any, preStop int64) int64 { ... },  // KEPT
        "shutdownTimeoutScript": func(spec any, preStop int64) string { ... }, // ADDED — new configs can use this
    })
```

> "We cannot ever remove or rename functions as these are used in previously shipped llmisvcconfig which would stop
> working on upgrade."

### Template Variable Stability (MIG-060)

```yaml
# Shipped llmisvcconfig references template variables by name:
# {{ .LLMInferenceService.Spec.Router.Scheduler.Pool.Spec.ExtensionRef.Name }}

# BAD: renaming the Go struct field changes the template variable
# type RouterSpec struct {
#     Scheduler *SchedulerSpec  →  SchedulingConfig *SchedulerSpec
# }
# All shipped configs referencing .Router.Scheduler break silently

# GOOD: if the Go struct field must change, keep the old template variable
# working via an alias or adapter in ReplaceVariables
```

## Testing

### Tests Must Fail (TST-020)

```python
# BAD: swallow assertion errors
try:
    assert len(traces) > 0
except AssertionError:
    logger.warning("traces not found")

# GOOD: fail or mark xfail with reason
assert len(traces) > 0, f"No traces found for {service}"
# or
@pytest.mark.xfail(reason="EPP may not export traces in all configs")
```

> "If the intention is to not fail the test, what are we actually getting out of this CI check? A log on a green check
> that nobody reads is not useful to catch regressions."

### Don't Skip Critical Checks (TST-050)

```python
# BAD: skip if prerequisite missing
if not is_rhcl_installed():
    pytest.skip("RHCL not installed")

# QUESTION: is RHCL expected to be installed before the test suite?
# If yes, skipping hides failures.
```

> "We expect RHCL to be installed before our test suite, so this should never happen. It might skip critical tests and
> we won't notice until someone reports it."

## Cross-Repo Coordination

### Image Injection (XREPO-010, CFG-020)

```
# When adding new images to params.env:
# 1. Add to config/overlays/odh/params.env
# 2. Open companion PR in opendatahub-operator to inject:
#    internal/controller/components/kserve/kserve_support.go
# 3. Update kustomization to inject for llmisvcconfig that use it
```

> "We will need to open a PR in the operator to inject/update these images."

### Module Integration (XREPO-020)

> "We need to integrate the overlay(s) with the operator module to have it apply the resources since currently they
> wouldn't be applied."

## Naming

### Resource Prefix (NAM-010)

```yaml
# BAD: generic name in shared namespace
name: llm-vllm-engine

# GOOD: prefixed, specific
name: kserve-llm-isvc-vllm-engine
```

> "I'd prefix it with `kserve-` so that we don't ever clash with other resources in the odh namespace and perhaps more
> specific `llm` -> `llm-isvc`."

## Bug-Derived Patterns

Patterns extracted from 342 real Jira bugs (93 Blocker, 63 Critical, 75 Major, 65 Normal).

### Upgrade Restart Risk (BUG-010)

```yaml
# BAD: annotation injected into pod template causes hash change on upgrade
metadata:
  annotations:
    serving.kserve.io/deployment-mode: "RawDeployment"  # this flows into pod template

# GOOD: annotations that affect pod template must be stable across versions
# Ask: "Does this change the pod template hash for existing Deployments?"
```

Real bugs:

- RHOAIENG-59339: router-scheduler pods unnecessarily redeploy during upgrade due to annotation injection changing pod
  template hash
- RHOAIENG-71245: pods redeployed during upgrade due to modelcar shell quoting change in entrypoint

### Wrong Image Tag (BUG-020)

```yaml
# BAD: placeholder image without kustomize replacement
image: controller:latest

# BAD: version mismatch — GA configs referencing EA images
image: quay.io/opendatahub/vllm:odh-v3.4.0  # but this is a 3.5 release

# GOOD: image in params.env + kustomize replacement + operator injection
# params.env:
kserve-llm-d-routing-sidecar=quay.io/opendatahub/llm-d-routing-sidecar:odh-v3.5-GA
```

Real bugs:

- RHOAIENG-69531: image tag odh-v3.5-EA2 does not exist — all tests fail with ImagePullBackOff
- RHOAIENG-55878: missing kustomize replacement leaves placeholder image `controller:latest`

### Security Context Breaks Device Injection (BUG-030)

```yaml
# BAD: readOnlyRootFilesystem breaks CDI GPU injection
securityContext:
  readOnlyRootFilesystem: true  # nvidia-cdi-hook needs to write to /

# BAD: runAsNonRoot in contexts that need procfs access
securityContext:
  runAsNonRoot: true  # breaks OCI modelcar procfs symlink on xKS

# GOOD: validate security context against ALL deployment targets
# Check: CDI GPU injection, OCI modelcar, xKS, FIPS
```

Real bugs:

- RHOAIENG-75488: readOnlyRootFilesystem: true breaks CDI-based GPU injection (BLOCKER)
- RHOAIENG-71150: readOnlyRootFilesystem must be disabled for nvidia-cdi-hook (BLOCKER)
- INFERENG-7332: runAsNonRoot blocks procfs symlink for OCI modelcar

### Missing Migration Logic (BUG-040)

```go
// BAD: version bump without migration
// Controller crashes on startup because old resources don't match new schema

// GOOD: migration with version detection and fallback
func (r *Reconciler) Reconcile(ctx context.Context, ...) {
    if needsMigration(existing) {
        if err := r.migrate(ctx, existing); err != nil {
            return err
        }
    }
    // normal reconciliation
}
```

Real bugs:

- RHOAIENG-58364: CrashLoopBackOff after upgrade 3.3→3.4 — missing migration logic
- RHOAIENG-54344: Deadlock during migration due to missing conversion webhook
- RHOAIENG-76305: tolerations/nodeSelector not injected after webhook migration

### Missing RBAC (BUG-050)

```yaml
# BAD: controller watches InferenceModelRewrites but no RBAC rule
# Results in: "cannot watch resource inferencemodelrewrites"

# GOOD: every watched resource needs RBAC
rules:
- apiGroups: ["inference.networking.k8s.io"]
  resources: ["inferencemodelrewrites"]
  verbs: ["get", "list", "watch"]
```

Real bugs:

- RHOAIENG-56779: EPP fails to watch inferencemodelrewrites — missing RBAC in distro ClusterRole
- RHOAIENG-54987: missing RBAC for clusterstoragecontainers blocks KServe reconciliation

### FIPS/TLS Compatibility (BUG-060)

```go
// BAD: binary uses non-FIPS-compliant crypto or CPU-specific instructions
// Crashes with FATAL FIPS SELFTEST FAILURE or SIGILL on specific CPUs

// BAD: flag mismatch between versions
// "flag provided but not defined: -enable-cert-reload"

// GOOD: verify binary on FIPS-enabled cluster and multiple CPU architectures
// GOOD: check flag compatibility between old and new versions
```

Real bugs:

- RHOAIENG-58354: tokenizer crashes with FATAL FIPS SELFTEST FAILURE
- INFERENG-6224: sidecar crashes with SIGILL on AKS nodes (AMD EPYC, Intel Cascade Lake)
- RHOAIENG-56379: router-scheduler fails with undefined flag `-enable-cert-reload`

### Monitoring Breakage (BUG-070)

```yaml
# BAD: hardcoded matchNamespace
spec:
  namespaceSelector:
    matchNames: ["redhat-ods-applications"]  # breaks in non-default namespace

# BAD: metrics port without NetworkPolicy rule
# Prometheus can't scrape because port 9090 is blocked

# GOOD: derive namespace from deployment context
# GOOD: add NetworkPolicy port for every metrics endpoint
```

Real bugs:

- INFERENG-5614: WVA servicemonitor matchNamespace field is hardcoded
- RHOAIENG-58209: metrics port 9090 blocked by NetworkPolicy
- INFERENG-7687: must patch networkpolicy for Prometheus to scrape WVA metrics

### Hardcoded Values (BUG-080)

```yaml
# BAD: hardcoded timeout breaks for large models
startupProbe:
  failureThreshold: 60
  periodSeconds: 10  # = 10 min max — too short for 70B+ models

# BAD: hardcoded secret value across all pods
env:
- name: OAUTH2_PROXY_COOKIE_SECRET
  value: "static-secret-here"  # same in every pod = security risk

# GOOD: make timeout configurable or derive from model size
# GOOD: generate unique secrets per deployment
```

Real bugs:

- RHOAIENG-75793: hardcoded 10-minute startupProbe causes termination during large model loads
- RHOAIENG-69776: hardcoded oauth-proxy cookie-secret in every runtime pod

### Multi-Node Edge Cases (BUG-110)

```python
# BAD: entrypoint only considers first NIC
NCCL_SOCKET_IFNAME=$(ip -o link show | head -1 | awk '{print $2}')

# BAD: metrics counted per pod in LWS — over-counts with multiple replicas
# Each LWS replica may have multiple metric-emitting pods

# GOOD: enumerate all NICs/HCAs, select by network type
# GOOD: use per-replica deduplication for metrics
```

Real bugs:

- INFERENG-6968: P/D entrypoint script only considers first NIC/HCA
- INFERENG-8439: LWS replicas with multiple metric-emitting pods are over-counted
- RHOAIENG-70416: Multi-node Ready condition stuck at Unknown despite all pods running

### Storage Initializer / Modelcar Injection (BUG-120)

```go
// BAD: init container argument list grows unbounded with model count
// With 100+ models, the argument list exceeds execve limits → deployment fails
args := []string{modelUri1, modelUri2, ..., modelUri150}  // "argument list too long"

// GOOD: use manifest file or ConfigMap for large model lists
// Write model URIs to a file, pass file path as single argument
```

```go
// BAD: mutating webhook strips storageUri when imagePullSecrets secret is deleted
// The webhook fires on Secret deletion and clears the storageUri annotation
func (w *Webhook) Handle(ctx context.Context, req admission.Request) {
    // Missing: guard against stale imagePullSecrets reference
}

// GOOD: guard storageUri mutation — only clear on explicit user action, not cascading deletes
```

```go
// BAD: hf:// URI downloads entire repo (ONNX, TF, Flax exports) when only safetensors needed
// BAD: HF_TOKEN env var not propagated from InferenceService to storage-initializer init container
// BAD: versioned model path (hf://org/model@v1.2) not resolved — downloads HEAD instead

// GOOD: filter downloads by required framework files
// GOOD: propagate all credential env vars to init containers
// GOOD: resolve version refs before download
```

```yaml
# BAD: storage-initializer binary without FIPS compliance
# Crashes with: FIPS check-payload failure on FIPS-enabled clusters

# BAD: storage-initializer not built for ppc64le/s390x
# Build failure on Power and Z architectures

# GOOD: verify storage-initializer binary on FIPS cluster AND multi-arch
```

For pod template hash stability of modelcar command strings, see CTL-100.

Real bugs:

- RHOAIENG-30376: storage-initializer argument list too long — single models fail to deploy (Blocker)
- RHOAIENG-60931: FIPS check-payload failure in storage-initializer binary (Blocker)
- RHOAIENG-50492: storage-initializer build failure on Power/Z (Blocker)
- RHOAIENG-69344: HF_TOKEN not propagated to storage-initializer init container
- RHOAIENG-69346: downloads entire HF repo instead of required files
- RHOAIENG-61105: mutating webhook strips storageUri when imagePullSecrets secret deleted
- RHOAIENG-50800: model deployment fails during storage-initializer download (Critical)
- RHOAIENG-34931: storage initializer can't handle versioned model storage paths
