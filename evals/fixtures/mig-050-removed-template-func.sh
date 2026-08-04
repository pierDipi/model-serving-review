#!/usr/bin/env bash
FIXTURE_NAME="mig-050-removed-template-func"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/config_merge.go <<'GO'
package controller

import (
	"text/template"
)

func ReplaceVariables(input string, spec interface{}) (string, error) {
	t, err := template.New("config").
		Funcs(map[string]any{
			"kvTransferConfig": func(spec any) string {
				return "kv-transfer-config"
			},
			"shutdownTimeout": func(spec any, preStop int64) int64 {
				return preStop + 30
			},
			"modelFormat": func(spec any) string {
				return "vllm"
			},
		}).
		Parse(input)
	if err != nil {
		return "", err
	}
	// execute template...
	return "", nil
}
GO
commit "initial config_merge with template functions"

write_file pkg/controller/config_merge.go <<'GO'
package controller

import (
	"text/template"
)

func ReplaceVariables(input string, spec interface{}) (string, error) {
	t, err := template.New("config").
		Funcs(map[string]any{
			// REMOVED: kvTransferConfig — was used in shipped llmisvcconfig files
			// RENAMED: shutdownTimeout → shutdownTimeoutScript
			"shutdownTimeoutScript": func(spec any, preStop int64) string {
				return fmt.Sprintf("sleep %d", preStop+30)
			},
			"modelFormat": func(spec any) string {
				return "vllm"
			},
		}).
		Parse(input)
	if err != nil {
		return "", err
	}
	return "", nil
}
GO
commit "remove kvTransferConfig and rename shutdownTimeout"

emit_repo
