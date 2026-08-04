#!/usr/bin/env bash
FIXTURE_NAME="clean-controller"
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

# Clean code following all best practices
write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type LLMServiceReconciler struct {
	Client client.Client
}

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	svc := &LLMService{}
	if err := r.Client.Get(ctx, req.NamespacedName, svc); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Exit early for deletion
	if !svc.DeletionTimestamp.IsZero() {
		return r.reconcileFinalization(ctx, svc)
	}

	// Guard nil before accessing nested fields
	if svc.Spec.Router == nil {
		return ctrl.Result{}, nil
	}

	if err := r.reconcileRouter(ctx, svc); err != nil {
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

func (r *LLMServiceReconciler) reconcileRouter(ctx context.Context, svc *LLMService) error {
	if svc.Spec.Router.Scheduler == nil {
		return nil
	}

	pool, err := r.getInferencePool(ctx, svc)
	if err != nil {
		if !apierrors.IsNotFound(err) && !meta.IsNoMatchError(err) {
			return err
		}
		return r.createInferencePool(ctx, svc)
	}

	return r.updateInferencePool(ctx, svc, pool)
}
GO

write_file pkg/controller/reconciler_test.go <<'GO'
package controller

import (
	"context"
	"testing"
)

func TestReconcile_NilRouter(t *testing.T) {
	svc := &LLMService{}
	r := &LLMServiceReconciler{}
	_, err := r.Reconcile(context.Background(), ctrl.Request{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}
GO
commit "add clean reconciler with exit-early, nil guards, and IsNoMatchError"

emit_repo
