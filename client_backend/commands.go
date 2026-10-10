package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"time"

	"nox.app/client-backend/internal/backup"
	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/prompt"
	"nox.app/client-backend/internal/server"
	"nox.app/client-backend/internal/vault"
)

// commands are noxd's subcommands, by name.
var commands = map[string]func(args []string) int{
	"link":     link,
	"unlock":   unlock,
	"password": password,
	"backup":   backupCommand,
	"restore":  restore,
}

// unlockTimeout bounds `noxd unlock` and `noxd password`: Argon2 and opening
// the database take seconds at most, and a server that answers nothing for
// minutes is not one to wait on.
const unlockTimeout = 2 * time.Minute

// The words the commands use for the server's refusals - the page's own
// (contracts/control-and-page.md).
var refusals = map[string]string{
	"wrong":    "Wrong password.",
	"short":    "Use at least 12 characters.",
	"mismatch": "The passwords don't match.",
}

const forgetWarning = "If you forget this password, the server's data can't be opened by anyone, including you."

// unlock is `noxd unlock` (047): the first password of a new server, asked
// twice, or the password of a locked one, asked once - from the terminal
// without echo, or line by line from standard input when that is not a
// terminal. It goes to the running server over its service page's listener;
// nothing is printed but what happened.
func unlock(args []string) int {
	cfg, err := config.LoadCommand("unlock", args, os.Getenv)
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd unlock:", err)
		return 2
	}
	ctx, cancel := context.WithTimeout(context.Background(), unlockTimeout)
	defer cancel()
	state, err := server.RequestState(ctx, cfg.StatusAddr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd unlock:", err)
		return 1
	}
	in := prompt.New(os.Stdin, os.Stderr)
	var pw, repeat string
	switch state {
	case "open":
		fmt.Println("This server is already unlocked.")
		return 0
	case "setup":
		if in.Terminal() {
			fmt.Fprintln(os.Stderr, "Set a password for this server.")
			fmt.Fprintln(os.Stderr, forgetWarning)
		}
		if pw, err = in.Password("Password: "); err == nil {
			repeat, err = in.Password("Repeat password: ")
		}
	default:
		pw, err = in.Password("Password: ")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd unlock:", err)
		return 1
	}
	if state == "setup" {
		// The rules first, here: nothing to send that the server would refuse.
		if code := checkNew(pw, repeat); code != "" {
			fmt.Fprintln(os.Stderr, refusals[code])
			return 1
		}
	}
	if err := server.RequestUnlock(ctx, cfg.StatusAddr, pw, repeat); err != nil {
		return reportRefusal("noxd unlock", err)
	}
	fmt.Println("Unlocked.")
	return 0
}

// password is `noxd password` (047): the current password, the new one and
// its repeat. The server re-seals its data key and touches nothing else.
func password(args []string) int {
	cfg, err := config.LoadCommand("password", args, os.Getenv)
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd password:", err)
		return 2
	}
	ctx, cancel := context.WithTimeout(context.Background(), unlockTimeout)
	defer cancel()
	in := prompt.New(os.Stdin, os.Stderr)
	current, err := in.Password("Current password: ")
	var next, repeat string
	if err == nil {
		next, err = in.Password("New password: ")
	}
	if err == nil {
		repeat, err = in.Password("Repeat new password: ")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd password:", err)
		return 1
	}
	if code := checkNew(next, repeat); code != "" {
		fmt.Fprintln(os.Stderr, refusals[code])
		return 1
	}
	if err := server.RequestPasswordChange(ctx, cfg.StatusAddr, current, next); err != nil {
		return reportRefusal("noxd password", err)
	}
	fmt.Println("Password changed.")
	return 0
}

// backupCommand is `noxd backup <file>` (047): the running server writes a
// backup of itself at file - one file, all of it encrypted, opened only by
// the server's password. The server keeps serving meanwhile; Ctrl+C stops
// the backup and leaves nothing behind.
func backupCommand(args []string) int {
	cfg, err := config.LoadBackup(args, os.Getenv)
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd backup:", err)
		return 2
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	if err := server.RequestBackup(ctx, cfg.StatusAddr, cfg.File); err != nil {
		return reportRefusal("noxd backup", err)
	}
	fmt.Println("Backup written to " + cfg.File)
	return 0
}

// restore is `noxd restore <file> -db <path> [-files <dir>]` (047): the
// backup unpacked onto an empty place, on this machine or any other, once the
// server's password opens it. No server runs for it - the place is empty. The
// restored server keeps its key, so devices go on without pairing, and gets a
// new journal id, so each of them reads the conversation again.
func restore(args []string) int {
	cfg, err := config.LoadRestore(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd restore:", err)
		return 2
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	in := prompt.New(os.Stdin, os.Stderr)
	_, err = backup.Restore(ctx, cfg.File, backup.Target{DBPath: cfg.DBPath, FilesPath: cfg.FilesPath}, func() (string, error) {
		return in.Password("Password: ")
	})
	switch {
	case errors.Is(err, vault.ErrWrongPassword):
		fmt.Fprintln(os.Stderr, refusals["wrong"]+" Nothing was restored.")
		return 1
	case err != nil:
		fmt.Fprintln(os.Stderr, "noxd restore:", err)
		return 1
	}
	fmt.Printf("Restored to %s. Start the server there and unlock it with the same password.\n", cfg.DBPath)
	return 0
}

// checkNew is the rule for a new password, as the server applies it: the
// refusal's code, or "" when it passes.
func checkNew(pw, repeat string) string {
	if vault.CheckPassword(pw) != nil {
		return "short"
	}
	if pw != repeat {
		return "mismatch"
	}
	return ""
}

// reportRefusal prints what the server said and returns the exit code.
func reportRefusal(command string, err error) int {
	var refused *server.CommandError
	if errors.As(err, &refused) {
		if words, ok := refusals[refused.Code]; ok {
			fmt.Fprintln(os.Stderr, words)
			return 1
		}
		switch refused.Code {
		case "state":
			fmt.Fprintln(os.Stderr, command+": the server is not in a state for this - "+
				"unlock it first, or it was unlocked or set up meanwhile")
		default:
			fmt.Fprintln(os.Stderr, command+":", refused.Message)
		}
		return 1
	}
	fmt.Fprintln(os.Stderr, command+":", err)
	return 1
}
