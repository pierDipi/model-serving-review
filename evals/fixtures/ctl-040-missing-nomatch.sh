#!/usr/bin/env bash
FIXTURE_NAME="ctl-040-missing-nomatch"
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

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type LLMServiceReconciler struct {
	Client client.Client
}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	svc, err := r.getLLMService(ctx, req)
	if err != nil {
		return ctrl.Result{}, err
	}

	// Reconcile LeaderWorkerSet — only checks IsNotFound, missing IsNoMatchError
	lws, err := r.getLeaderWorkerSet(ctx, svc)
	if err != nil {
		if apierrors.IsNotFound(err) {
			// LWS not found, create it
			return ctrl.Result{}, r.createLeaderWorkerSet(ctx, svc)
		}
		// Missing: meta.IsNoMatchError check for when LWS CRD is not installed
		return ctrl.Result{}, err
	}

	// Reconcile InferencePool — same missing check
	pool, err := r.getInferencePool(ctx, svc)
	if err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, r.createInferencePool(ctx, svc)
		}
		// Missing: meta.IsNoMatchError for CRD-not-installed case
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}
GO
commit "add resource reconciliation without IsNoMatchError"

emit_repo
