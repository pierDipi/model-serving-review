#!/usr/bin/env bash
FIXTURE_NAME="multi-rule-controller"
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

# Multiple violations in a single file
write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct {
	Recorder record.EventRecorder
}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	svc, err := r.getLLMService(ctx, req)
	if err != nil {
		return ctrl.Result{}, err
	}

	// VIOLATION 1: CTL-020 — nil panic risk, no guards on nested access
	poolName := svc.Spec.Router.Scheduler.Pool.Spec.ExtensionRef.Name
	fmt.Printf("Pool: %s\n", poolName)

	// VIOLATION 2: CTL-010 — deep nesting
	if !svc.DeletionTimestamp.IsZero() {
		if svc.HasFinalizer("serving.kserve.io/cleanup") {
			if svc.Status.IsReady() {
				if svc.Spec.Router != nil {
					r.cleanupRouter(ctx, svc)
				}
			}
		}
	} else {
		if svc.Spec.Router != nil {
			if svc.Spec.Router.Scheduler != nil {
				r.reconcileScheduler(ctx, svc)
			}
		}
	}

	// VIOLATION 3: CTL-030 — event on success
	r.Recorder.Event(svc, corev1.EventTypeNormal, "Reconciled", "Successfully reconciled")
	r.Recorder.Event(svc, corev1.EventTypeNormal, "NoOp", "No changes needed")

	return ctrl.Result{}, nil
}
GO
commit "add reconciler with multiple violations"

emit_repo
