#!/usr/bin/env bash
FIXTURE_NAME="sec-075-plaintext-http"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/metrics_client.go <<'GO'
package controller

type MetricsCollector struct{}
GO
commit "initial metrics collector"

write_file pkg/controller/metrics_client.go <<'GO'
package controller

import (
	"fmt"
	"io"
	"net/http"
)

type MetricsCollector struct {
	client   *http.Client
	endpoint string
}

func NewMetricsCollector(endpoint string) *MetricsCollector {
	return &MetricsCollector{
		client:   &http.Client{},
		endpoint: endpoint,
	}
}

func (m *MetricsCollector) CollectMetrics() ([]byte, error) {
	// Outbound HTTP call without TLS to an external metrics endpoint
	resp, err := m.client.Get(fmt.Sprintf("http://%s/metrics", m.endpoint))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func (m *MetricsCollector) PushMetrics(data []byte) error {
	// Another plaintext HTTP connection
	resp, err := m.client.Post(
		fmt.Sprintf("http://%s/api/v1/push", m.endpoint),
		"application/json",
		nil,
	)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}

// This is fine — localhost communication between containers in same pod
func (m *MetricsCollector) QueryLocal() ([]byte, error) {
	resp, err := m.client.Get("http://127.0.0.1:9090/metrics")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}
GO
commit "add metrics client with plaintext HTTP"

emit_repo
