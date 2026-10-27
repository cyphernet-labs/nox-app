package server

import (
	"sync"
	"time"
)

// uploadWriters keeps ONE request writing each part (043).
//
// A PUT whose connection died silently - the phone left home and its packets
// go nowhere - goes on waiting for bytes until its stall deadline. A new PUT
// for the same file writing beside it would put the late bytes of the old
// one into the same part at the old one's offset, in the middle of the new
// one's. So whoever comes for a file interrupts the request writing it and
// waits for it to let go.
//
// The mutex is infrastructure, the same class as the token store and the
// connection registry: it guards which request holds which part, nothing the
// wire can see (CLAUDE.md invariant 7 names it).
type uploadWriters struct {
	mu     sync.Mutex
	active map[string]*writer
}

// writer is one request holding a part.
type writer struct {
	// interrupt ends the holder's writing at once. Called with no lock held.
	interrupt func()
	// done closes when the holder has stopped writing and made what it
	// received durable.
	done chan struct{}
}

func newUploadWriters() *uploadWriters {
	return &uploadWriters{active: make(map[string]*writer)}
}

// take makes the caller the one writer of fileID. A writer already there is
// interrupted, and take waits up to wait for it to let go; ok is false when it
// did not. The caller calls release once it has stopped writing - safe to
// call more than once.
//
// A writer that registered while take waited is interrupted in turn: the
// newest request for a file is the one its client is still waiting on.
func (u *uploadWriters) take(fileID string, interrupt func(), wait time.Duration) (release func(), ok bool) {
	timer := time.NewTimer(wait)
	defer timer.Stop()
	for {
		u.mu.Lock()
		prev := u.active[fileID]
		if prev == nil {
			me := &writer{interrupt: interrupt, done: make(chan struct{})}
			u.active[fileID] = me
			u.mu.Unlock()
			return sync.OnceFunc(func() { u.release(fileID, me) }), true
		}
		u.mu.Unlock()

		prev.interrupt()
		select {
		case <-prev.done:
		case <-timer.C:
			return nil, false
		}
	}
}

// interrupt stops whoever is writing fileID and waits up to wait for them to
// let go, registering nothing. The continuation of an upload asks how much
// arrived; only a PUT writes.
func (u *uploadWriters) interrupt(fileID string, wait time.Duration) {
	u.mu.Lock()
	prev := u.active[fileID]
	u.mu.Unlock()
	if prev == nil {
		return
	}
	prev.interrupt()
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case <-prev.done:
	case <-timer.C:
	}
}

// release drops me from the registry - unless a newer writer already took its
// place, whose registration is not mine to remove - and tells anyone waiting
// on me that I let go.
func (u *uploadWriters) release(fileID string, me *writer) {
	u.mu.Lock()
	if u.active[fileID] == me {
		delete(u.active, fileID)
	}
	u.mu.Unlock()
	close(me.done)
}
