#!/usr/bin/env bash
FIXTURE_NAME="sec-060-auth-fallthrough"
source "$(dirname "$0")/common.sh"
init_repo "https://github.com/opendatahub-io/odh-model-controller.git"

write_file internal/controller/resources/authpolicy.go <<'GO'
package resources

func buildAuthPolicy(namespace, name string) *AuthPolicy {
	return &AuthPolicy{
		Name:      name,
		Namespace: namespace,
	}
}
GO
commit "initial authpolicy builder"

write_file internal/controller/resources/authpolicy.go <<'GO'
package resources

import "fmt"

func buildAuthPolicy(namespace, name, modelRoutingHeader string) *AuthPolicy {
	policy := &AuthPolicy{
		Name:      name,
		Namespace: namespace,
		Rules: []AuthRule{
			{
				// Model-level access: checks SAR for the specific model
				Name: "model-access",
				When: []Predicate{
					{
						Condition: fmt.Sprintf("'%s' in request.headers", modelRoutingHeader),
					},
				},
				Action: "CUSTOM",
			},
			{
				// Instance-level access: checks SAR for the inference service
				// BUG: A request with the model routing header that FAILS model-access
				// will fall through to this rule and get authorized against the
				// instance-level SAR, enabling cross-tenant escalation.
				Name: "inference-access",
				When: []Predicate{
					{
						// No guard to prevent fallthrough from model-access
						Condition: fmt.Sprintf("!request.path.startsWith('/v1/')"),
					},
				},
				Action: "CUSTOM",
			},
		},
	}
	return policy
}
GO
commit "add multi-path auth with fallthrough vulnerability"

emit_repo
