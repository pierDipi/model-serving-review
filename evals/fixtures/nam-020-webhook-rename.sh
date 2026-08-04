#!/usr/bin/env bash
FIXTURE_NAME="nam-020-webhook-rename"
source "$(dirname "$0")/common.sh"
init_repo

write_file config/webhook/manifests.yaml <<'YAML'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: kserve-validating-webhook-configuration
webhooks:
  - name: llminferenceservice.kserve-webhook-server.validator
    clientConfig:
      service:
        name: kserve-webhook-server-service
        namespace: kserve
        path: /validate-serving-kserve-io-v1alpha1-llminferenceservice
    rules:
      - apiGroups: ["serving.kserve.io"]
        apiVersions: ["v1alpha1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["llminferenceservices"]
YAML
commit "initial webhook config"

write_file config/webhook/manifests.yaml <<'YAML'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: kserve-validating-webhook-configuration
webhooks:
  # Webhook name changed — creates ghost webhook during upgrade
  - name: llminferenceservice-v1alpha2.kserve-webhook-server.validator
    clientConfig:
      service:
        name: kserve-webhook-server-service
        namespace: kserve
        path: /validate-serving-kserve-io-v1alpha2-llminferenceservice
    rules:
      - apiGroups: ["serving.kserve.io"]
        apiVersions: ["v1alpha2"]
        operations: ["CREATE", "UPDATE"]
        resources: ["llminferenceservices"]
YAML
commit "rename webhook for v1alpha2"

emit_repo
