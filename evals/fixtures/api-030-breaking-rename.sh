#!/usr/bin/env bash
FIXTURE_NAME="api-030-breaking-rename"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/apis/serving/v1beta1/types.go <<'GO'
package v1beta1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type LLMInferenceServiceSpec struct {
	// Router configures the routing layer.
	// +optional
	Router *RouterSpec `json:"router,omitempty"`
}

type RouterSpec struct {
	// Scheduler configures the scheduling backend.
	// +optional
	Scheduler *SchedulerSpec `json:"scheduler,omitempty"`
}

type SchedulerSpec struct {
	// Pool references the InferencePool.
	// +optional
	Pool *PoolReference `json:"pool,omitempty"`
}

type PoolReference struct {
	Name string `json:"name"`
}

type LLMInferenceService struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              LLMInferenceServiceSpec `json:"spec,omitempty"`
}
GO
commit "initial LLMInferenceService types"

write_file pkg/apis/serving/v1beta1/types.go <<'GO'
package v1beta1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type LLMInferenceServiceSpec struct {
	// RoutingConfig configures the routing layer.
	// Renamed from Router to RoutingConfig for clarity.
	// +optional
	RoutingConfig *RoutingConfigSpec `json:"routingConfig,omitempty"`
}

type RoutingConfigSpec struct {
	// SchedulingBackend configures the scheduling backend.
	// Renamed from Scheduler to SchedulingBackend.
	// +optional
	SchedulingBackend *SchedulingBackendSpec `json:"schedulingBackend,omitempty"`
}

type SchedulingBackendSpec struct {
	// PoolRef references the InferencePool.
	// Renamed from Pool to PoolRef.
	// +optional
	PoolRef *PoolReference `json:"poolRef,omitempty"`
}

type PoolReference struct {
	Name string `json:"name"`
}

type LLMInferenceService struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              LLMInferenceServiceSpec `json:"spec,omitempty"`
}
GO
commit "rename Router to RoutingConfig, Scheduler to SchedulingBackend"

emit_repo
