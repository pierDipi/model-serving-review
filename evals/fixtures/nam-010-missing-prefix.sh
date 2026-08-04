#!/usr/bin/env bash
FIXTURE_NAME="nam-010-missing-prefix"
source "$(dirname "$0")/common.sh"
init_repo

write_file config/default/service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: kserve-controller-manager
  namespace: kserve
spec:
  ports:
    - port: 443
      targetPort: 9443
  selector:
    control-plane: kserve-controller-manager
YAML
commit "initial service"

write_file config/default/service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: kserve-controller-manager
  namespace: kserve
spec:
  ports:
    - port: 443
      targetPort: 9443
  selector:
    control-plane: kserve-controller-manager
---
apiVersion: v1
kind: Service
metadata:
  # Missing kserve- prefix — violates NAM-010
  name: llm-vllm-engine
  namespace: kserve
spec:
  ports:
    - name: grpc
      port: 8033
      targetPort: 8033
  selector:
    app: vllm-engine
---
apiVersion: v1
kind: ConfigMap
metadata:
  # Also missing prefix
  name: llm-scorer-config
  namespace: kserve
data:
  config.yaml: |
    scorer:
      type: kv-cache
YAML
commit "add new resources without kserve- prefix"

emit_repo
