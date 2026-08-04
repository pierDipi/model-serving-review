#!/usr/bin/env bash
FIXTURE_NAME="sec-010-missing-san"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/llmisvc/workload_tls.go <<'GO'
package llmisvc

import (
	"crypto/x509"
	"crypto/x509/pkix"
	"net"
)

func buildCertTemplate(svcName, namespace string) *x509.Certificate {
	return &x509.Certificate{
		Subject: pkix.Name{
			CommonName: svcName,
		},
		DNSNames: []string{
			svcName,
			svcName + "." + namespace + ".svc",
			svcName + "." + namespace + ".svc.cluster.local",
		},
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")},
	}
}
GO
commit "initial TLS cert builder"

write_file pkg/controller/llmisvc/workload_tls.go <<'GO'
package llmisvc

import (
	"crypto/x509"
	"crypto/x509/pkix"
	"net"
)

func buildCertTemplate(svcName, namespace string) *x509.Certificate {
	return &x509.Certificate{
		Subject: pkix.Name{
			CommonName: svcName,
		},
		DNSNames: []string{
			svcName,
			svcName + "." + namespace + ".svc",
			svcName + "." + namespace + ".svc.cluster.local",
		},
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")},
	}
}

// New tokenizer sidecar service added but NOT included in the certificate SANs above.
// The tokenizer listens on port 8081 and needs TLS for inter-service communication.
func reconcileTokenizerSidecar(ctx context.Context, svc *LLMService) error {
	sidecar := corev1.Container{
		Name:  "tokenizer",
		Image: "quay.io/opendatahub/tokenizer:v0.1.0",
		Ports: []corev1.ContainerPort{
			{ContainerPort: 8081, Name: "tokenizer"},
		},
		// TLS flags not passed — SEC-020 violation too
		Args: []string{
			"--port=8081",
			// Missing: --tls-cert-file, --tls-key-file
		},
	}
	return addSidecar(ctx, svc, sidecar)
}
GO
commit "add tokenizer sidecar without TLS SAN"

emit_repo
