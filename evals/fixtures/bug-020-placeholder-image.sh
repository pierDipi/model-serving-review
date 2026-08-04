#!/usr/bin/env bash
FIXTURE_NAME="bug-020-placeholder-image"
source "$(dirname "$0")/common.sh"
init_repo "https://github.com/opendatahub-io/kserve.git"

write_file config/internal/base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kserve-controller-manager
spec:
  template:
    spec:
      containers:
        - name: manager
          image: kserve-controller:latest
YAML
commit "initial deployment"

write_file config/internal/base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kserve-controller-manager
spec:
  template:
    spec:
      containers:
        - name: manager
          # Placeholder image — should be replaced by kustomize
          image: controller:latest
        - name: kube-rbac-proxy
          # Another placeholder with no replacement entry
          image: gcr.io/kubebuilder/kube-rbac-proxy:latest
YAML

write_file config/overlays/odh/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../internal/base
# Missing: replacements for controller:latest and kube-rbac-proxy:latest
YAML
commit "add placeholder images without kustomize replacements"

emit_repo
