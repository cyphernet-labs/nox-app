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

func recv(t *testing.T, s *Subscriber) Envelope {
	t.Helper()
	select {
	case env, ok := <-s.C():
		if !ok {
			t.Fatal("subscriber channel closed unexpectedly")
		}
		return env
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for frame")
	}
	return Envelope{}
}

func env(s string) Envelope {
	return Envelope{Stripped: []byte(s)}
}

func TestBroadcastReachesAllSubscribers(t *testing.T) {
	h := runHub(t)
	a := NewSubscriber(func() {})
	b := NewSubscriber(func() {})
	h.Register(a)
	h.Register(b)

	h.Broadcast(env("one"))

	if got := string(recv(t, a).Stripped); got != "one" {
		t.Fatalf("a got %q", got)
	}
	if got := string(recv(t, b).Stripped); got != "one" {
		t.Fatalf("b got %q", got)
	}
}

func TestEnvelopeFrameForSelectsVariantByAuthor(t *testing.T) {
	e := Envelope{AuthorID: "Anna", Full: []byte("full"), Stripped: []byte("stripped")}
	if got := string(e.FrameFor("Anna")); got != "full" {
		t.Fatalf("author variant = %q", got)
	}
	if got := string(e.FrameFor("Bob")); got != "stripped" {
		t.Fatalf("other variant = %q", got)
	}
	shared := Envelope{Stripped: []byte("same")}
	if got := string(shared.FrameFor("")); got != "same" {
		t.Fatalf("anonymous recipient of shared envelope = %q", got)
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
		h.Broadcast(env("x"))
		recv(t, fast)
	}

	// Fan-out order over the map is arbitrary, so the fast subscriber may
	// receive the last frame before the hub reaches the slow one - poll.
	deadlineDrop := time.After(time.Second)
	for !dropped.Load() {
		select {
		case <-deadlineDrop:
			t.Fatal("slow subscriber was not dropped")
		case <-time.After(5 * time.Millisecond):
		}
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
		h.Broadcast(env("x"))
		h.Unregister(NewSubscriber(func() {}))
	}()
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("hub operations blocked after stop")
	}
}
