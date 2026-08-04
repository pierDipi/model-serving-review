#!/usr/bin/env bash
FIXTURE_NAME="bug-120-arg-overflow"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/utils/storage.go <<'GO'
package utils

func BuildStorageInitArgs(modelURI string) []string {
	return []string{modelURI, "/mnt/models"}
}
GO
commit "initial storage utils"

write_file pkg/utils/storage.go <<'GO'
package utils

import "fmt"

func BuildStorageInitArgs(modelURIs []string, mountPath string) []string {
	// Appends each model URI as a separate argument with no limit.
	// With 100+ models, this exceeds execve argument list limits (128KB).
	args := []string{}
	for _, uri := range modelURIs {
		args = append(args, fmt.Sprintf("--model-uri=%s", uri))
		args = append(args, fmt.Sprintf("--model-path=%s/%s", mountPath, modelName(uri)))
	}
	return args
}

func BuildClusterStorageContainerArgs(containers []ClusterStorageContainer) []string {
	args := []string{}
	for _, c := range containers {
		for _, model := range c.Models {
			// Same unbounded pattern
			args = append(args, "--download", model.URI, model.Path)
		}
	}
	return args
}
GO
commit "add unbounded argument list in storage initializer"

emit_repo
