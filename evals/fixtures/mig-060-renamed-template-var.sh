#!/usr/bin/env bash
FIXTURE_NAME="mig-060-renamed-template-var"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/apis/serving/v1alpha1/types.go <<'GO'
package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type LLMInferenceServiceSpec struct {
	// Router configures the routing layer.
	// Template variable: {{ .LLMInferenceService.Spec.Router.Scheduler.Pool.Spec.ExtensionRef.Name }}
	Router *RouterSpec `json:"router,omitempty"`
}

type RouterSpec struct {
	Scheduler *SchedulerSpec `json:"scheduler,omitempty"`
}

type SchedulerSpec struct {
	Pool *PoolSpec `json:"pool,omitempty"`
	Image string   `json:"image,omitempty"`
}

type PoolSpec struct {
	Spec PoolInnerSpec `json:"spec,omitempty"`
}

type PoolInnerSpec struct {
	ExtensionRef *ExtensionRef `json:"extensionRef,omitempty"`
}

type ExtensionRef struct {
	Name string `json:"name"`
}
GO
commit "initial types with template variables"

write_file pkg/apis/serving/v1alpha1/types.go <<'GO'
package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type LLMInferenceServiceSpec struct {
	// RoutingConfig configures the routing layer.
	// RENAMED from Router — breaks shipped template variable:
	// {{ .LLMInferenceService.Spec.Router.Scheduler.Pool.Spec.ExtensionRef.Name }}
	// now requires:
	// {{ .LLMInferenceService.Spec.RoutingConfig.SchedulingConfig.PoolConfig.Spec.ExtensionRef.Name }}
	RoutingConfig *RoutingConfigSpec `json:"routingConfig,omitempty"`
}

type RoutingConfigSpec struct {
	// RENAMED from Scheduler
	SchedulingConfig *SchedulingConfigSpec `json:"schedulingConfig,omitempty"`
}

type SchedulingConfigSpec struct {
	// RENAMED from Pool
	PoolConfig *PoolSpec `json:"poolConfig,omitempty"`
	Image      string    `json:"image,omitempty"`
}

type PoolSpec struct {
	Spec PoolInnerSpec `json:"spec,omitempty"`
}

type PoolInnerSpec struct {
	ExtensionRef *ExtensionRef `json:"extensionRef,omitempty"`
}

type ExtensionRef struct {
	Name string `json:"name"`
}
GO
commit "rename struct fields used as template variables"

emit_repo
