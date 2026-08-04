#!/usr/bin/env bash
FIXTURE_NAME="ctl-100-annotation-injection"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/deployment_reconciler.go <<'GO'
package controller

import (
	"context"
	appsv1 "k8s.io/api/apps/v1"
)

func (r *LLMServiceReconciler) reconcileDeployment(ctx context.Context, svc *LLMService) error {
	deployment := &appsv1.Deployment{}
	deployment.Name = svc.Name
	deployment.Namespace = svc.Namespace

	deployment.Spec.Template.Spec.Containers = []corev1.Container{
		{
			Name:  "kserve-container",
			Image: svc.Spec.Image,
		},
	}

	return r.Client.Update(ctx, deployment)
}
GO
commit "initial deployment reconciler"

write_file pkg/controller/deployment_reconciler.go <<'GO'
package controller

import (
	"context"
	appsv1 "k8s.io/api/apps/v1"
)

func (r *LLMServiceReconciler) reconcileDeployment(ctx context.Context, svc *LLMService) error {
	deployment := &appsv1.Deployment{}
	deployment.Name = svc.Name
	deployment.Namespace = svc.Namespace

	// Inject annotation into pod template — this changes the pod template hash
	// and triggers a rollout on controller upgrade even when the CR hasn't changed
	if deployment.Spec.Template.Annotations == nil {
		deployment.Spec.Template.Annotations = map[string]string{}
	}
	deployment.Spec.Template.Annotations["serving.kserve.io/deployment-mode"] = "RawDeployment"
	deployment.Spec.Template.Annotations["serving.kserve.io/controller-version"] = "v0.14"

	deployment.Spec.Template.Spec.Containers = []corev1.Container{
		{
			Name:  "kserve-container",
			Image: svc.Spec.Image,
		},
	}

	return r.Client.Update(ctx, deployment)
}
GO
commit "inject annotations into pod template"

emit_repo
