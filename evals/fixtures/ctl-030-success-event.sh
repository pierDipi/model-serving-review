#!/usr/bin/env bash
FIXTURE_NAME="ctl-030-success-event"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct {
	Recorder record.EventRecorder
}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	return ctrl.Result{}, nil
}
GO
commit "initial controller"

write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
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

	if err := r.reconcileDeployment(ctx, svc); err != nil {
		r.Recorder.Event(svc, corev1.EventTypeWarning, "ReconcileFailed", err.Error())
		return ctrl.Result{}, err
	}

	// Emit event on every successful reconcile — causes API server load
	r.Recorder.Event(svc, corev1.EventTypeNormal, "Reconciled", "Successfully reconciled all components")

	// Also emit on no-op
	r.Recorder.Event(svc, corev1.EventTypeNormal, "NoChange", "No changes needed")

	return ctrl.Result{}, nil
}
GO
commit "add event emission on success"

emit_repo
