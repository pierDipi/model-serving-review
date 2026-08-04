#!/usr/bin/env bash
FIXTURE_NAME="sec-030-insecure-skip"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/client.go <<'GO'
package controller

import (
	"net/http"
)

func newHTTPClient() *http.Client {
	return &http.Client{}
}
GO
commit "initial HTTP client"

write_file pkg/controller/client.go <<'GO'
package controller

import (
	"crypto/tls"
	"net/http"
)

func newHTTPClient() *http.Client {
	return &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true, // TODO: add proper cert validation
			},
		},
	}
}

func newMetricsClient(endpoint string) *http.Client {
	return &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		},
	}
}
GO
commit "add InsecureSkipVerify to HTTP clients"

emit_repo
