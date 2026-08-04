#!/usr/bin/env bash
FIXTURE_NAME="cfg-020-missing-params"
source "$(dirname "$0")/common.sh"
init_repo "https://github.com/opendatahub-io/kserve.git"

write_file config/llmisvcconfig/config-llm-template.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-template
spec:
  containers:
    - name: kserve-container
      image: quay.io/opendatahub/vllm:odh-v3.4-GA
YAML

write_file config/overlays/odh/params.env <<'ENV'
kserve-controller=quay.io/opendatahub/kserve-controller:odh-v3.4-GA
kserve-router=quay.io/opendatahub/kserve-router:odh-v3.4-GA
ENV
commit "initial config with params.env"

write_file config/llmisvcconfig/config-llm-template.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-template
spec:
  containers:
    - name: kserve-container
      image: quay.io/opendatahub/vllm:odh-v3.4-GA
  sidecars:
    - name: tokenizer-sidecar
      # New image not in params.env, no kustomize replacement entry
      image: quay.io/opendatahub/tokenizer:v0.1.0
      ports:
        - containerPort: 8081
YAML
commit "add tokenizer sidecar with image not in params.env"

emit_repo
