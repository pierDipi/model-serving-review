#!/usr/bin/env bash
FIXTURE_NAME="bug-080-hardcoded-timeout"
source "$(dirname "$0")/common.sh"
init_repo

write_file config/llmisvcconfig/config-llm-template.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-template
spec:
  containers:
    - name: kserve-container
      image: quay.io/opendatahub/vllm:odh-v3.5-GA
YAML
commit "initial config"

write_file config/llmisvcconfig/config-llm-template.yaml <<'YAML'
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceServiceConfig
metadata:
  name: kserve-llm-isvc-template
spec:
  containers:
    - name: kserve-container
      image: quay.io/opendatahub/vllm:odh-v3.5-GA
      # Hardcoded startupProbe timeout — 10 minutes too short for 70B+ models
      startupProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 60
      env:
        - name: OAUTH2_PROXY_COOKIE_SECRET
          # Hardcoded secret — same in every pod, security risk
          value: "dGhpcy1pcy1hLXN0YXRpYy1zZWNyZXQ="
        - name: METRICS_NAMESPACE
          # Hardcoded namespace — breaks in non-default deployments
          value: "redhat-ods-applications"
YAML
commit "add hardcoded timeout, secret, and namespace"

emit_repo
