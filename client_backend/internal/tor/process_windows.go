//go:build windows

package tor

import (
	"os/exec"
	"syscall"
)

// detach starts tor in a process group of its own, which also turns Ctrl+C off
// for it: the console's Ctrl+C is the server's to handle, and tor must outlive
// the server's drain. tor dies with the server anyway: it is owned
// (TAKEOWNERSHIP, __OwningControllerProcess).
func detach(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP}
}
