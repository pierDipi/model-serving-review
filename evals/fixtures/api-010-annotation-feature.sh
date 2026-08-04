#!/usr/bin/env bash
FIXTURE_NAME="api-010-annotation-feature"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/apis/serving/v1beta1/types.go <<'GO'
package v1beta1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type InferenceServiceSpec struct {
	Predictor PredictorSpec `json:"predictor"`
}

type PredictorSpec struct {
	Model *ModelSpec `json:"model,omitempty"`
}

type ModelSpec struct {
	ModelFormat ModelFormat `json:"modelFormat,omitempty"`
	Runtime     *string     `json:"runtime,omitempty"`
}

type ModelFormat struct {
	Name    string  `json:"name"`
	Version *string `json:"version,omitempty"`
}

type InferenceService struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              InferenceServiceSpec `json:"spec,omitempty"`
}
GO
commit "initial API types"

write_file pkg/apis/serving/v1beta1/types.go <<'GO'
package v1beta1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type InferenceServiceSpec struct {
	Predictor PredictorSpec `json:"predictor"`
}

type PredictorSpec struct {
	Model *ModelSpec `json:"model,omitempty"`
}

type ModelSpec struct {
	ModelFormat ModelFormat `json:"modelFormat,omitempty"`
	Runtime     *string     `json:"runtime,omitempty"`
}

type ModelFormat struct {
	Name    string  `json:"name"`
	Version *string `json:"version,omitempty"`
}

type InferenceService struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              InferenceServiceSpec `json:"spec,omitempty"`
}

// New feature: batch inference scheduling
// Implemented via annotation instead of a typed API field
// Users set: serving.kserve.io/batch-size: "32"
//            serving.kserve.io/batch-timeout: "500ms"
//            serving.kserve.io/batch-max-latency: "5s"
// These should be typed fields in the spec, not annotations.
const (
	BatchSizeAnnotation      = "serving.kserve.io/batch-size"
	BatchTimeoutAnnotation   = "serving.kserve.io/batch-timeout"
	BatchMaxLatencyAnnotation = "serving.kserve.io/batch-max-latency"
)

func GetBatchSize(svc *InferenceService) string {
	if svc.Annotations == nil {
		return ""
	}
	return svc.Annotations[BatchSizeAnnotation]
}

func GetBatchTimeout(svc *InferenceService) string {
	if svc.Annotations == nil {
		return ""
	}
	return svc.Annotations[BatchTimeoutAnnotation]
}
GO
commit "add batch inference via annotations"

emit_repo
