package tor

import (
	"bufio"
	"context"
	"errors"
	"net"
	"strings"
	"testing"
	"time"
)

// fakeControl is the tor side of a control connection: it reads command lines
// and lets the test answer them line by line.
type fakeControl struct {
	t     *testing.T
	peer  net.Conn
	lines *bufio.Reader
}

func newFakeControl(t *testing.T) (*Conn, *fakeControl) {
	t.Helper()
	client, server := net.Pipe()
	c := newConn(client)
	t.Cleanup(func() {
		_ = c.Close()
		_ = server.Close()
	})
	return c, &fakeControl{t: t, peer: server, lines: bufio.NewReader(server)}
}

// expect reads one command line and returns it.
func (f *fakeControl) expect() string {
	f.t.Helper()
	_ = f.peer.SetReadDeadline(time.Now().Add(5 * time.Second))
	line, err := f.lines.ReadString('\n')
	if err != nil {
		f.t.Fatalf("fake tor: read command: %v", err)
	}
	return strings.TrimRight(line, "\r\n")
}

func (f *fakeControl) write(raw string) {
	f.t.Helper()
	_ = f.peer.SetWriteDeadline(time.Now().Add(5 * time.Second))
	if _, err := f.peer.Write([]byte(raw)); err != nil {
		f.t.Fatalf("fake tor: write: %v", err)
	}
}

// answer runs fn against the next command on its own goroutine, so the test
// can call Command and have it answered.
func (f *fakeControl) answer(fn func(cmd string)) chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		fn(f.expect())
	}()
	return done
}

func TestASingleLineReplyIsSuccess(t *testing.T) {
	c, tor := newFakeControl(t)
	done := tor.answer(func(cmd string) {
		if cmd != "TAKEOWNERSHIP" {
			t.Errorf("command = %q", cmd)
		}
		tor.write("250 OK\r\n")
	})
	lines, err := c.Command(t.Context(), "TAKEOWNERSHIP")
	<-done
	if err != nil || len(lines) != 1 || lines[0] != "OK" {
		t.Fatalf("Command = %q, %v", lines, err)
	}
}

func TestMultiLineAndDataRepliesArriveWhole(t *testing.T) {
	c, tor := newFakeControl(t)
	done := tor.answer(func(string) {
		tor.write("250+circuit-status=\r\n12 BUILT $A~a PURPOSE=HS_SERVICE_REND\r\n..dot-stuffed\r\n.\r\n250 OK\r\n")
	})
	value, err := c.GetInfo(t.Context(), "circuit-status")
	<-done
	if err != nil {
		t.Fatalf("GetInfo: %v", err)
	}
	if value != "12 BUILT $A~a PURPOSE=HS_SERVICE_REND\n.dot-stuffed" {
		t.Fatalf("value = %q", value)
	}

	done = tor.answer(func(string) {
		tor.write("250-version=0.4.9.13 (git-3c575400909efe65)\r\n250 OK\r\n")
	})
	version, err := c.GetInfo(t.Context(), "version")
	<-done
	if err != nil || version != "0.4.9.13 (git-3c575400909efe65)" {
		t.Fatalf("GetInfo(version) = %q, %v", version, err)
	}
}

func TestAnEventInTheMiddleOfAReplyGoesToEvents(t *testing.T) {
	c, tor := newFakeControl(t)
	done := tor.answer(func(string) {
		tor.write("250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=50\r\n")
		tor.write("650 HS_DESC UPLOADED abc UNKNOWN $F~n\r\n")
		tor.write("250 OK\r\n")
	})
	value, err := c.GetInfo(t.Context(), "status/bootstrap-phase")
	<-done
	if err != nil || value != "NOTICE BOOTSTRAP PROGRESS=50" {
		t.Fatalf("GetInfo = %q, %v", value, err)
	}
	select {
	case ev := <-c.Events():
		if ev != "HS_DESC UPLOADED abc UNKNOWN $F~n" {
			t.Fatalf("event = %q", ev)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the event never arrived")
	}
}

// The error must not repeat the command: ADD_ONION carries the private key and
// every client key, and errors end up in the log and on the status page.
func TestARefusedCommandNamesTheVerbAndNothingElse(t *testing.T) {
	c, tor := newFakeControl(t)
	const secret = "PRIVATEKEYMATERIAL0123456789abcdefghijklmnopqrstuvwxyz"
	done := tor.answer(func(string) {
		tor.write("512 Invalid key " + secret + "\r\n")
	})
	_, err := c.Command(t.Context(), "ADD_ONION ED25519-V3:"+secret+" Flags=V3Auth Port=443,127.0.0.1:1 ClientAuthV3="+secret)
	<-done
	var refused *CommandError
	if !errors.As(err, &refused) || refused.Verb != "ADD_ONION" || refused.Code != 512 {
		t.Fatalf("err = %v, want CommandError{ADD_ONION, 512}", err)
	}
	if strings.Contains(err.Error(), secret) || strings.Contains(err.Error(), "Invalid key") {
		t.Fatalf("the error carries the command or the reply: %q", err)
	}
}

func TestTheCookieNeverAppearsInAnAuthenticationError(t *testing.T) {
	c, tor := newFakeControl(t)
	cookie := []byte{0xde, 0xad, 0xbe, 0xef}
	done := tor.answer(func(cmd string) {
		if cmd != "AUTHENTICATE DEADBEEF" {
			t.Errorf("command = %q", cmd)
		}
		tor.write("515 Authentication failed\r\n")
	})
	err := c.Authenticate(t.Context(), cookie)
	<-done
	if err == nil || strings.Contains(strings.ToUpper(err.Error()), "DEADBEEF") {
		t.Fatalf("err = %v", err)
	}
}

func TestATimedOutCommandClosesTheConnection(t *testing.T) {
	c, tor := newFakeControl(t)
	go func() { _ = tor.expect() }() // read it, never answer

	ctx, cancel := context.WithTimeout(t.Context(), 100*time.Millisecond)
	defer cancel()
	if _, err := c.Command(ctx, "GETINFO version"); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("err = %v, want DeadlineExceeded", err)
	}
	select {
	case <-c.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the connection outlived a command whose reply never came")
	}
}

func TestTorGoingAwayEndsTheConnection(t *testing.T) {
	c, tor := newFakeControl(t)
	go func() {
		_ = tor.expect()
		_ = tor.peer.Close()
	}()
	if _, err := c.Command(t.Context(), "GETINFO version"); !errors.Is(err, ErrClosed) {
		t.Fatalf("err = %v, want ErrClosed", err)
	}
	if _, ok := <-c.Events(); ok {
		t.Fatal("events channel still open after the connection ended")
	}
}
