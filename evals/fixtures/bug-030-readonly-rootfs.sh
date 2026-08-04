#!/usr/bin/env bash
FIXTURE_NAME="bug-030-readonly-rootfs"
source "$(dirname "$0")/common.sh"
init_repo

write_file config/llmisvcconfig/config-llm-template.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-vllm
spec:
  containers:
    - name: kserve-container
      image: quay.io/opendatahub/vllm:odh-v3.5-GA
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
YAML
commit "initial config"

write_file config/llmisvcconfig/config-llm-template.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-vllm
spec:
  containers:
    - name: kserve-container
      image: quay.io/opendatahub/vllm:odh-v3.5-GA
      securityContext:
        # readOnlyRootFilesystem breaks CDI-based GPU injection (nvidia-cdi-hook)
        # and OCI modelcar serving
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
YAML
commit "add readOnlyRootFilesystem to container security context"

emit_repo
