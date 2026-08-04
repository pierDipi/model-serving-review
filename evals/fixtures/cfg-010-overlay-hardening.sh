#!/usr/bin/env bash
FIXTURE_NAME="cfg-010-overlay-hardening"
source "$(dirname "$0")/common.sh"
init_repo "https://github.com/opendatahub-io/kserve.git"

write_file config/llmisvcconfig/config-llm-base.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-base
spec:
  containers:
    - name: kserve-container
      securityContext:
        runAsNonRoot: true
        readOnlyRootFilesystem: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
YAML
commit "initial base config with security context"

write_file config/overlays/odh/accelerator.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-nvidia-gpu
spec:
  containers:
    - name: kserve-container
      image: quay.io/opendatahub/vllm:latest
      # Re-setting security context already defined in base — violates CFG-010
      securityContext:
        runAsNonRoot: true
        readOnlyRootFilesystem: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      resources:
        limits:
          nvidia.com/gpu: "1"
YAML
commit "add accelerator overlay that re-sets base hardening"

emit_repo
