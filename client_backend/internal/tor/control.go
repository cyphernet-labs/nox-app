package tor

import (
	"bufio"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

// eventBuffer is how many asynchronous events wait for the supervisor. The
// events this server subscribes to are rare - bootstrap progress, version
// verdicts, descriptor uploads - and a full buffer drops rather than blocks:
// the reader must never stall behind events, or the reply to the command in
// flight would wait behind them too.
const eventBuffer = 256

// maxLine bounds one line from tor. tor is our own child, but a reader that
// grows without limit is a reader somebody eventually feeds without limit.
const maxLine = 1 << 20

// ErrClosed means the control connection is gone - tor exited, or the
// connection was closed after a command timed out.
var ErrClosed = errors.New("tor control connection closed")

// CommandError is a command tor answered with a failure.
//
// It names the VERB and the status code, never the command's arguments and
// never tor's reply text. ADD_ONION carries the onion service's private key and
// every client key, AUTHENTICATE carries the cookie, and an error that repeated
// either would carry it into the log and onto the status page (FR-031).
type CommandError struct {
	Verb string
	Code int
}

func (e *CommandError) Error() string {
	return fmt.Sprintf("tor refused %s (%d)", e.Verb, e.Code)
}

// Conn is one connection to tor's control port.
//
// One goroutine reads it and sorts what arrives: asynchronous events (status
// 650) go to Events, everything else is the reply to the one command in
// flight. Commands are sent by one goroutine - the supervisor - one at a time,
// so there is no queue to own and no lock to take; a second concurrent caller
// would be a bug in the caller.
type Conn struct {
	conn      net.Conn
	replies   chan reply
	events    chan string
	done      chan struct{}
	closeOnce sync.Once
}

type reply struct {
	code  int
	lines []string
}

// Dial connects to a control port on loopback.
func Dial(ctx context.Context, addr string) (*Conn, error) {
	var d net.Dialer
	c, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("dial the tor control port: %w", err)
	}
	return newConn(c), nil
}

func newConn(c net.Conn) *Conn {
	cc := &Conn{
		conn: c,
		// One slot: the reply to the command in flight. A late reply to a
		// command that timed out never needs a second one, because a timeout
		// closes the connection.
		replies: make(chan reply, 1),
		events:  make(chan string, eventBuffer),
		done:    make(chan struct{}),
	}
	go cc.readLoop()
	return cc
}

// Events delivers asynchronous events, without the "650 " prefix. Closed when
// the connection ends.
func (c *Conn) Events() <-chan string { return c.events }

// Done is closed when the connection has ended.
func (c *Conn) Done() <-chan struct{} { return c.done }

// Close ends the connection. With TAKEOWNERSHIP sent, this is also what stops
// tor.
func (c *Conn) Close() error {
	var err error
	c.closeOnce.Do(func() { err = c.conn.Close() })
	return err
}

// Command sends one command line and returns tor's reply lines, each without
// its status prefix: "250-version=0.4.9.13" arrives as "version=0.4.9.13", and
// a data block ("250+key=" … ".") as "key=" followed by its lines joined with
// "\n". Any 2xx status is success.
//
// A command that times out closes the connection: its reply may still arrive,
// and the next command would read it as its own. The supervisor reconnects
// from scratch rather than guess which reply is whose.
func (c *Conn) Command(ctx context.Context, line string) ([]string, error) {
	verb := line
	if i := strings.IndexByte(line, ' '); i >= 0 {
		verb = line[:i]
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = c.conn.SetWriteDeadline(deadline)
	} else {
		_ = c.conn.SetWriteDeadline(time.Time{})
	}
	if _, err := io.WriteString(c.conn, line+"\r\n"); err != nil {
		_ = c.Close()
		return nil, fmt.Errorf("send %s: %w", verb, ErrClosed)
	}
	select {
	case rep := <-c.replies:
		if rep.code < 200 || rep.code > 299 {
			return nil, &CommandError{Verb: verb, Code: rep.code}
		}
		return rep.lines, nil
	case <-c.done:
		return nil, fmt.Errorf("%s: %w", verb, ErrClosed)
	case <-ctx.Done():
		_ = c.Close()
		return nil, fmt.Errorf("%s: %w", verb, ctx.Err())
	}
}

// Authenticate proves the control cookie. The cookie travels as hex and, like
// every argument, never appears in an error.
func (c *Conn) Authenticate(ctx context.Context, cookie []byte) error {
	_, err := c.Command(ctx, "AUTHENTICATE "+strings.ToUpper(hex.EncodeToString(cookie)))
	return err
}

// GetInfo asks for one key and returns its value. A multi-line value comes back
// with its lines joined by "\n".
func (c *Conn) GetInfo(ctx context.Context, key string) (string, error) {
	lines, err := c.Command(ctx, "GETINFO "+key)
	if err != nil {
		return "", err
	}
	prefix := key + "="
	for _, l := range lines {
		if strings.HasPrefix(l, prefix) {
			return strings.TrimPrefix(strings.TrimPrefix(l, prefix), "\n"), nil
		}
	}
	return "", fmt.Errorf("GETINFO %s: no value in the reply", key)
}

// readLoop is the only reader of the connection.
func (c *Conn) readLoop() {
	defer close(c.done)
	defer close(c.events)
	r := bufio.NewReaderSize(c.conn, 4096)
	var acc, eventLines []string
	for {
		line, err := readLine(r)
		if err != nil {
			return
		}
		if len(line) < 4 {
			continue
		}
		code, err := strconv.Atoi(line[:3])
		if err != nil {
			continue
		}
		sep, text := line[3], line[4:]
		if sep == '+' {
			data, err := readData(r)
			if err != nil {
				return
			}
			text += "\n" + data
		}
		if code == 650 {
			eventLines = append(eventLines, text)
			if sep == ' ' {
				ev := strings.Join(eventLines, "\n")
				eventLines = nil
				select {
				case c.events <- ev:
				default:
					// Dropped rather than blocking the reader: the supervisor
					// re-reads the state it cares about on a timer anyway.
				}
			}
			continue
		}
		acc = append(acc, text)
		if sep == ' ' {
			select {
			case c.replies <- reply{code: code, lines: acc}:
			default:
				// Nobody is waiting and the slot is taken: a reply to a
				// command that was never sent. Nothing sane follows from here.
				_ = c.Close()
				return
			}
			acc = nil
		}
	}
}

func readLine(r *bufio.Reader) (string, error) {
	var b strings.Builder
	for {
		chunk, isPrefix, err := r.ReadLine()
		if err != nil {
			return "", err
		}
		b.Write(chunk)
		if b.Len() > maxLine {
			return "", errors.New("tor control line too long")
		}
		if !isPrefix {
			return b.String(), nil
		}
	}
}

// readData reads a data block up to its terminating "." line, undoing the
// dot-stuffing tor applies to lines that begin with one.
func readData(r *bufio.Reader) (string, error) {
	var lines []string
	size := 0
	for {
		line, err := readLine(r)
		if err != nil {
			return "", err
		}
		if line == "." {
			return strings.Join(lines, "\n"), nil
		}
		if strings.HasPrefix(line, "..") {
			line = line[1:]
		}
		size += len(line)
		if size > maxLine {
			return "", errors.New("tor control data block too long")
		}
		lines = append(lines, line)
	}
}
