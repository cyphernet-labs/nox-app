//go:build windows

package main

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"

	"golang.org/x/sys/windows/svc"
)

// execute runs the service's Execute with a server that does what run says,
// sends it the requests given, and returns what it reported to the manager.
func execute(t *testing.T, run func(ctx context.Context) error, requests ...svc.Cmd) (bool, uint32, []svc.State, *service) {
	t.Helper()
	s := &service{logger: slog.New(slog.NewTextHandler(io.Discard, nil)), run: run}
	reqs := make(chan svc.ChangeRequest, len(requests))
	for _, cmd := range requests {
		reqs <- svc.ChangeRequest{Cmd: cmd}
	}
	status := make(chan svc.Status, 8)
	specific, code := s.Execute(nil, reqs, status)
	close(status)
	var states []svc.State
	for st := range status {
		states = append(states, st.State)
	}
	return specific, code, states, s
}

func TestAStopTheManagerAskedForIsACleanExitEvenWhenTheShutdownRanOut(t *testing.T) {
	for _, cmd := range []svc.Cmd{svc.Stop, svc.Shutdown} {
		// A transfer still moving holds the shutdown past its deadline, and
		// the server says so - the stop was still asked for.
		run := func(ctx context.Context) error {
			<-ctx.Done()
			return errors.New("shutdown: context deadline exceeded")
		}
		specific, code, states, s := execute(t, run, cmd)
		if specific || code != 0 || s.failed {
			t.Fatalf("cmd %v: exit = (%v, %d), failed = %v; want a clean exit, or the manager restarts the server",
				cmd, specific, code, s.failed)
		}
		if len(states) != 2 || states[0] != svc.Running || states[1] != svc.StopPending {
			t.Fatalf("cmd %v: states = %v, want Running then StopPending", cmd, states)
		}
	}
}

func TestAStopTheManagerAskedForThatShutsDownCleanlyIsACleanExit(t *testing.T) {
	run := func(ctx context.Context) error {
		<-ctx.Done()
		return nil
	}
	if specific, code, _, s := execute(t, run, svc.Stop); specific || code != 0 || s.failed {
		t.Fatalf("exit = (%v, %d), failed = %v; want a clean exit", specific, code, s.failed)
	}
}

func TestAServerThatStopsByItselfIsAFailureTheManagerRestarts(t *testing.T) {
	run := func(context.Context) error {
		return errors.New("service page on 127.0.0.1:8081: address in use")
	}
	specific, code, _, s := execute(t, run)
	if !specific || code != 1 || !s.failed {
		t.Fatalf("exit = (%v, %d), failed = %v; want a service-specific failure", specific, code, s.failed)
	}
}
