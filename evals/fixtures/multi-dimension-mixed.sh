#!/usr/bin/env bash
FIXTURE_NAME="multi-dimension-mixed"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/reconciler.go <<'GO'
package controller

func placeholder() {}
GO

write_file pkg/apis/serving/v1beta1/types.go <<'GO'
package v1beta1

type InferenceServiceSpec struct {
	Predictor PredictorSpec `json:"predictor"`
}

type PredictorSpec struct {
	Model *ModelSpec `json:"model,omitempty"`
}

type ModelSpec struct {
	ModelFormat string `json:"modelFormat,omitempty"`
}
GO

write_file config/default/service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: kserve-controller-manager
spec:
  ports:
    - port: 443
YAML
commit "initial files"

# Changes spanning controller, API, and config
write_file pkg/controller/reconciler.go <<'GO'
package controller

import (
	"context"
	ctrl "sigs.k8s.io/controller-runtime"
)

func (r *LLMServiceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	svc, err := r.getLLMService(ctx, req)
	if err != nil {
		return ctrl.Result{}, err
	}

	// CTL-010: deep nesting
	if !svc.DeletionTimestamp.IsZero() {
		if svc.HasFinalizer("cleanup") {
			if svc.Status.IsReady() {
				r.cleanup(ctx, svc)
			}
		}
	}

	return ctrl.Result{}, nil
}
GO

write_file pkg/apis/serving/v1beta1/types.go <<'GO'
package v1beta1

type InferenceServiceSpec struct {
	Predictor           PredictorSpec        `json:"predictor"`
	SpeculativeDecoding *SpeculativeDecoding `json:"speculativeDecoding,omitempty"`
}

type PredictorSpec struct {
	Model *ModelSpec `json:"model,omitempty"`
}

type ModelSpec struct {
	ModelFormat string `json:"modelFormat,omitempty"`
}

// API-040: redundant naming
type SpeculativeDecoding struct {
	Speculator SpeculatorSpec `json:"speculator"`
}

type SpeculatorSpec struct {
	SpeculatorModel string `json:"speculatorModel"`
}
GO

write_file config/default/service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: kserve-controller-manager
spec:
  ports:
    - port: 443
---
apiVersion: v1
kind: Service
metadata:
  # NAM-010: missing kserve- prefix
  name: llm-engine-service
spec:
  ports:
    - port: 8080
YAML
commit "changes spanning controller, API, and config"

emit_repo
