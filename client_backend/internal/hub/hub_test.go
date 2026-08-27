package hub

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

func runHub(t *testing.T) *Hub {
	t.Helper()
	h := New()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	return h
}

func recv(t *testing.T, s *Subscriber) []byte {
	t.Helper()
	select {
	case frame, ok := <-s.C():
		if !ok {
			t.Fatal("subscriber channel closed unexpectedly")
		}
		return frame
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for frame")
	}
	return nil
}

func TestBroadcastReachesAllSubscribers(t *testing.T) {
	h := runHub(t)
	a := NewSubscriber(func() {})
	b := NewSubscriber(func() {})
	h.Register(a)
	h.Register(b)

	h.Broadcast([]byte("one"))

	if got := string(recv(t, a)); got != "one" {
		t.Fatalf("a got %q", got)
	}
	if got := string(recv(t, b)); got != "one" {
		t.Fatalf("b got %q", got)
	}
}

func TestSlowSubscriberIsDroppedOthersKeepReceiving(t *testing.T) {
	h := runHub(t)

	var dropped atomic.Bool
	slow := NewSubscriber(func() { dropped.Store(true) })
	fast := NewSubscriber(func() { t.Error("fast subscriber must not be dropped") })
	h.Register(slow)
	h.Register(fast)

	// Overflow the slow subscriber: its buffer holds subscriberBuffer frames.
	for range subscriberBuffer + 1 {
		h.Broadcast([]byte("x"))
		recv(t, fast)
	}

	if !dropped.Load() {
		t.Fatal("slow subscriber was not dropped")
	}
	// Its channel must be closed by the hub.
	deadline := time.After(time.Second)
	for {
		select {
		case _, ok := <-slow.C():
			if !ok {
				return
			}
		case <-deadline:
			t.Fatal("slow subscriber channel never closed")
		}
	}
}

func TestUnregisterClosesChannel(t *testing.T) {
	h := runHub(t)
	s := NewSubscriber(func() {})
	h.Register(s)
	h.Unregister(s)

	deadline := time.After(time.Second)
	for {
		select {
		case _, ok := <-s.C():
			if !ok {
				return
			}
		case <-deadline:
			t.Fatal("channel never closed after Unregister")
		}
	}
}

func TestOperationsAfterStopDoNotBlock(t *testing.T) {
	h := New()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.Run(ctx)
	}()
	cancel()
	<-done

	finished := make(chan struct{})
	go func() {
		defer close(finished)
		h.Register(NewSubscriber(func() {}))
		h.Broadcast([]byte("x"))
		h.Unregister(NewSubscriber(func() {}))
	}()
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("hub operations blocked after stop")
	}
}
