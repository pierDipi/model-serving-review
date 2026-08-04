#!/usr/bin/env bash
FIXTURE_NAME="api-020-strict-enum"
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
}

type ModelFormat struct {
	Name string `json:"name"`
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

// DecodingMethod defines the decoding strategy for text generation.
// +kubebuilder:validation:Enum=greedy;beam_search;top_k;top_p
type DecodingMethod string

const (
	DecodingGreedy     DecodingMethod = "greedy"
	DecodingBeamSearch DecodingMethod = "beam_search"
	DecodingTopK       DecodingMethod = "top_k"
	DecodingTopP       DecodingMethod = "top_p"
)

type InferenceServiceSpec struct {
	Predictor PredictorSpec `json:"predictor"`
}

type PredictorSpec struct {
	Model *ModelSpec `json:"model,omitempty"`
}

type ModelSpec struct {
	ModelFormat ModelFormat `json:"modelFormat,omitempty"`
	// +optional
	DecodingStrategy *DecodingMethod `json:"decodingStrategy,omitempty"`
}

type ModelFormat struct {
	Name string `json:"name"`
}

type InferenceService struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              InferenceServiceSpec `json:"spec,omitempty"`
}
GO
commit "add strict enum for decoding strategy"

emit_repo
