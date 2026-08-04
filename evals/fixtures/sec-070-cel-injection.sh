#!/usr/bin/env bash
FIXTURE_NAME="sec-070-cel-injection"
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
commit "initial authpolicy"

write_file internal/controller/resources/authpolicy.go <<'GO'
package resources

import "fmt"

func buildAuthPolicy(namespace, name string, config AuthPolicyConfig) *AuthPolicy {
	// Template variable interpolated directly into CEL expression
	// without validation. If config.ModelRoutingHeader contains
	// CEL-significant characters (quotes, parens, backslashes),
	// it enables CEL injection.
	celExpr := fmt.Sprintf(
		"request.headers['%s'].matches('^publishers/[^/]+/models/.+$')",
		config.ModelRoutingHeader, // NOT VALIDATED
	)

	policy := &AuthPolicy{
		Name:      name,
		Namespace: namespace,
		Rules: []AuthRule{
			{
				Name: "model-routing",
				When: []Predicate{
					{Condition: celExpr},
				},
			},
		},
	}
	return policy
}
GO
commit "add CEL expression with unvalidated template variable"

emit_repo
