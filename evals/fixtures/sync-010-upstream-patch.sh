#!/usr/bin/env bash
FIXTURE_NAME="sync-010-upstream-patch"
source "$(dirname "$0")/common.sh"
init_repo "https://github.com/opendatahub-io/kserve.git"

write_file config/default/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../crd
  - ../rbac
  - ../manager
  - ../webhook
  - ../certmanager
YAML
commit "initial kustomization"

write_file config/default/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# ODH-SPECIFIC: removed certmanager since we use OpenShift service-ca
# This is a direct modification of an upstream-synced file
resources:
  - ../crd
  - ../rbac
  - ../manager
  - ../webhook
  # - ../certmanager  # ODH: removed, using service-ca instead
YAML
commit "modify upstream file directly instead of using ODH overlay"

emit_repo
