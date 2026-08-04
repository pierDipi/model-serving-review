#!/usr/bin/env bash
FIXTURE_NAME="ctl-100-shell-quoting"
source "$(dirname "$0")/common.sh"
init_repo

write_file pkg/controller/modelcar.go <<'GO'
package controller

import (
	"fmt"
	"strings"
)

func buildModelcarCommand(modelPaths []string, mountPath string) string {
	cmds := []string{}
	for _, p := range modelPaths {
		cmds = append(cmds, fmt.Sprintf("mkdir -p '%s' && ln -sf '%s' '%s'", mountPath, p, mountPath))
	}
	return strings.Join(cmds, " && ")
}
GO
commit "initial modelcar command builder"

write_file pkg/controller/modelcar.go <<'GO'
package controller

import (
	"fmt"
	"strings"
)

// shellQuote unconditionally wraps in quotes — changes existing command strings
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

func buildModelcarCommand(modelPaths []string, mountPath string) string {
	cmds := []string{}
	for _, p := range modelPaths {
		// This changes the command string from:
		//   mkdir -p '/mnt/models' && ln -sf '/path' '/mnt/models'
		// to:
		//   mkdir -p '/mnt/models' && ln -sf '/path' '/mnt/models'
		// For paths without special chars, quoting was already done, so the
		// outer quote wrapping changes the string → different pod template hash → restart
		cmds = append(cmds, fmt.Sprintf("mkdir -p %s && ln -sf %s %s",
			shellQuote(mountPath), shellQuote(p), shellQuote(mountPath)))
	}
	return strings.Join(cmds, " && ")
}
GO
commit "change shell quoting in modelcar commands"

emit_repo
