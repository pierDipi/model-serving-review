#!/usr/bin/env bash
FIXTURE_NAME="tst-010-no-regression-test"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) reconcileDeployment(ctx context.Context, svc *LLMService) error {
	deployment := r.buildDeployment(svc)
	return r.Client.Update(ctx, deployment)
}
GO
commit "initial controller"

# Bug fix without accompanying test
write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	ctrl "sigs.k8s.io/controller-runtime"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) reconcileDeployment(ctx context.Context, svc *LLMService) error {
	deployment := r.buildDeployment(svc)

	existing, err := r.getDeployment(ctx, svc)
	if err != nil {
		if apierrors.IsNotFound(err) {
			return r.Client.Create(ctx, deployment)
		}
		return err
	}

	// Fix: prevent nil pointer dereference when existing deployment
	// has no containers (regression from upgrade path)
	if len(existing.Spec.Template.Spec.Containers) == 0 {
		return r.Client.Update(ctx, deployment)
	}

	// Fix: preserve existing resource requests during reconciliation
	// to avoid resetting user-configured values
	for i, c := range existing.Spec.Template.Spec.Containers {
		if i < len(deployment.Spec.Template.Spec.Containers) {
			deployment.Spec.Template.Spec.Containers[i].Resources = c.Resources
		}
	}

	return r.Client.Update(ctx, deployment)
}
GO
commit "fix nil pointer and resource preservation bugs"

emit_repo
