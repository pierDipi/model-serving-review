#!/usr/bin/env bash
FIXTURE_NAME="bug-050-missing-rbac"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	ctrl "sigs.k8s.io/controller-runtime"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&LLMService{}).
		Complete(r)
}
GO

write_file config/rbac/role.yaml <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kserve-manager-role
rules:
  - apiGroups: ["serving.kserve.io"]
    resources: ["llminferenceservices"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
YAML
commit "initial controller with RBAC"

write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	ctrl "sigs.k8s.io/controller-runtime"
	inferenceapi "sigs.k8s.io/gateway-api-inference-extension/api/v1alpha2"
)

type LLMServiceReconciler struct{}

func (r *LLMServiceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&LLMService{}).
		// New CRD watches added but no matching RBAC entries
		Watches(&inferenceapi.InferenceModelRewrite{}, handler.EnqueueRequestForOwner()).
		Watches(&inferenceapi.InferencePool{}, handler.EnqueueRequestForOwner()).
		Complete(r)
}
GO
commit "add CRD watches without RBAC entries"

emit_repo
