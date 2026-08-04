#!/usr/bin/env bash
FIXTURE_NAME="ctl-020-nil-panic"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	return ctrl.Result{}, nil
}
GO
commit "initial controller"

write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	"fmt"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	svc, err := r.getLLMService(ctx, req)
	if err != nil {
		return ctrl.Result{}, err
	}

	// Direct access to deeply nested spec fields without nil guards
	poolName := svc.Spec.Router.Scheduler.Pool.Spec.ExtensionRef.Name
	fmt.Printf("Pool name: %s\n", poolName)

	schedulerImage := svc.Spec.Router.Scheduler.Image
	fmt.Printf("Scheduler image: %s\n", schedulerImage)

	return ctrl.Result{}, nil
}
GO
commit "access nested spec fields without nil guards"

emit_repo
