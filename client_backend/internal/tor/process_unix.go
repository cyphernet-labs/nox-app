//go:build unix

package tor

import (
	"os/exec"
	"syscall"
)

// detach puts tor in a process group of its own. A Ctrl+C in the terminal
// running the server goes to the whole foreground group, and tor would leave
// at once - while the server is still draining, with onion devices being told
// goodbye through it, and the supervisor would take the exit for a crash and
// start another tor mid-shutdown. tor dies with the server anyway: it is owned
// (TAKEOWNERSHIP, __OwningControllerProcess).
//
// systemd's default KillMode=control-group signals every process of the unit
// whatever its group, so a unit file wants KillMode=mixed for the same reason.
func detach(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}
