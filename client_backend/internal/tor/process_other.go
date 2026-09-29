//go:build !unix && !windows

package tor

import "os/exec"

// detach has nothing to do where there are no process groups to leave.
func detach(*exec.Cmd) {}
