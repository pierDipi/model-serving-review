#!/usr/bin/env bash
FIXTURE_NAME="clean-config"
source "$(dirname "$0")/common.sh"
init_repo "https://github.com/opendatahub-io/kserve.git"

write_file config/overlays/odh/params.env <<'ENV'
kserve-controller=quay.io/opendatahub/kserve-controller:odh-v3.4-GA
ENV

write_file config/overlays/odh/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../default
YAML
commit "initial ODH overlay"

# Clean config change: new image properly added to params.env with kustomize replacement
write_file config/overlays/odh/params.env <<'ENV'
kserve-controller=quay.io/opendatahub/kserve-controller:odh-v3.5-GA
kserve-router=quay.io/opendatahub/kserve-router:odh-v3.5-GA
ENV

write_file config/overlays/odh/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../default
replacements:
  - source:
      kind: ConfigMap
      name: params
      fieldPath: data.kserve-router
    targets:
      - select:
          kind: Deployment
          name: kserve-router
        fieldPaths:
          - spec.template.spec.containers.[name=router].image
YAML

write_file config/default/kserve-router-service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: kserve-router
  namespace: kserve
spec:
  ports:
    - name: https
      port: 443
      targetPort: 8443
YAML
commit "add router image to params.env with kustomize replacement"

emit_repo
