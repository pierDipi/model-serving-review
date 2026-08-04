#!/usr/bin/env bash
FIXTURE_NAME="bug-090-missing-netpol"
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
    - name: https
      port: 443
      targetPort: 9443
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
    - name: https
      port: 443
      targetPort: 9443
    # New metrics port added but no NetworkPolicy rule
    - name: metrics
      port: 9090
      targetPort: 9090
    # New webhook port
    - name: webhook
      port: 9443
      targetPort: 9443
YAML

write_file config/default/networkpolicy.yaml <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kserve-controller-network-policy
  namespace: kserve
spec:
  podSelector:
    matchLabels:
      control-plane: kserve-controller-manager
  ingress:
    - ports:
        - port: 443
          protocol: TCP
      # Missing: port 9090 for Prometheus scraping
      # Missing: port 9443 for webhook
YAML
commit "add new service ports without NetworkPolicy"

emit_repo
