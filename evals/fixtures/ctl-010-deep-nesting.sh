#!/usr/bin/env bash
FIXTURE_NAME="ctl-010-deep-nesting"
source "$(dirname "$0")/common.sh"
init_repo

# Initial state: empty controller package
write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	return ctrl.Result{}, nil
}
GO
commit "initial controller"

# Change: add deeply nested if-else logic
write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	svc, err := r.getLLMService(ctx, req)
	if err != nil {
		return ctrl.Result{}, err
	}

	if !svc.DeletionTimestamp.IsZero() {
		if svc.HasFinalizer("serving.kserve.io/cleanup") {
			if svc.Status.IsReady() {
				if svc.Spec.Router != nil {
					// deeply nested cleanup logic
					err := r.cleanupRouter(ctx, svc)
					if err != nil {
						return ctrl.Result{}, fmt.Errorf("cleanup router: %w", err)
					}
				}
			}
			r.removeFinalizer(svc)
		}
	} else {
		if svc.Spec.Router != nil {
			if svc.Spec.Router.Scheduler != nil {
				if svc.Spec.Router.Scheduler.Pool != nil {
					// deeply nested reconcile logic
					err := r.reconcilePool(ctx, svc)
					if err != nil {
						return ctrl.Result{}, err
					}
				}
			}
		}
	}

	return ctrl.Result{}, nil
}
GO
commit "add reconcile logic with deep nesting"

emit_repo
