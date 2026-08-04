#!/usr/bin/env bash
FIXTURE_NAME="xrepo-010-missing-companion"
source "$(dirname "$0")/common.sh"
init_repo "https://github.com/opendatahub-io/kserve.git"

write_file config/overlays/odh/params.env <<'ENV'
kserve-controller=quay.io/opendatahub/kserve-controller:odh-v3.4-GA
kserve-router=quay.io/opendatahub/kserve-router:odh-v3.4-GA
ENV
commit "initial params.env"

write_file config/overlays/odh/params.env <<'ENV'
kserve-controller=quay.io/opendatahub/kserve-controller:odh-v3.4-GA
kserve-router=quay.io/opendatahub/kserve-router:odh-v3.4-GA
kserve-llm-d-routing-sidecar=quay.io/opendatahub/llm-d-routing-sidecar:odh-v3.5-GA
kserve-llm-d-epp=quay.io/opendatahub/llm-d-epp:odh-v3.5-GA
ENV
commit "add new images to params.env"

emit_repo
