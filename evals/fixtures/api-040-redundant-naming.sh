#!/usr/bin/env bash
FIXTURE_NAME="api-040-redundant-naming"
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
GO
commit "initial API types"

write_file pkg/apis/serving/v1beta1/types.go <<'GO'
package v1beta1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type InferenceServiceSpec struct {
	Predictor            PredictorSpec         `json:"predictor"`
	SpeculativeDecoding  *SpeculativeDecoding  `json:"speculativeDecoding,omitempty"`
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

// SpeculativeDecoding configures speculative decoding.
type SpeculativeDecoding struct {
	// Speculator configures the speculator model.
	// Redundant: speculativeDecoding.speculator is repetitive.
	Speculator SpeculatorSpec `json:"speculator"`
}

type SpeculatorSpec struct {
	SpeculatorModel  string `json:"speculatorModel"`
	SpeculatorTokens int    `json:"speculatorNumTokens"`
}
GO
commit "add speculative decoding with redundant naming"

emit_repo
