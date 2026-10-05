package server

import (
	"testing"
	"time"
)

// holder takes fileID and lets go the moment it is interrupted, the way a
// PUT whose read was woken stops and returns.
func holder(t *testing.T, w *uploadWriters, fileID string) (interrupted <-chan struct{}) {
	t.Helper()
	stop := make(chan struct{}, 1)
	release, ok := w.take(fileID, func() {
		select {
		case stop <- struct{}{}:
		default:
		}
	}, time.Second)
	if !ok {
		t.Fatal("take on a free file did not succeed")
	}
	seen := make(chan struct{})
	go func() {
		<-stop
		close(seen)
		release()
	}()
	return seen
}

func TestTakeOnAFreeFileRegistersAtOnce(t *testing.T) {
	w := newUploadWriters()
	release, ok := w.take("f_1", func() {}, time.Millisecond)
	if !ok {
		t.Fatal("take on a free file failed")
	}
	release()
	// Released: the next one is free to take it.
	if _, ok := w.take("f_1", func() {}, time.Millisecond); !ok {
		t.Fatal("take after release failed")
	}
}

func TestASecondTakeInterruptsTheFirstAndWaitsForItToLetGo(t *testing.T) {
	w := newUploadWriters()
	interrupted := holder(t, w, "f_1")

	release, ok := w.take("f_1", func() {}, 5*time.Second)
	if !ok {
		t.Fatal("second take did not get the file")
	}
	defer release()
	select {
	case <-interrupted:
	default:
		t.Fatal("the first writer was never interrupted")
	}
}

func TestATakeGivesUpWhenTheHolderDoesNotLetGo(t *testing.T) {
	w := newUploadWriters()
	interruptions := 0
	stuck, ok := w.take("f_1", func() { interruptions++ }, time.Millisecond)
	if !ok {
		t.Fatal("take on a free file failed")
	}
	defer stuck()

	start := time.Now()
	if _, ok := w.take("f_1", func() {}, 50*time.Millisecond); ok {
		t.Fatal("take succeeded while the holder kept the file")
	}
	if waited := time.Since(start); waited < 50*time.Millisecond {
		t.Fatalf("take gave up after %v, before its wait was over", waited)
	}
	if interruptions != 1 {
		t.Fatalf("the holder was interrupted %d times, want once", interruptions)
	}
}

func TestInterruptWaitsForTheHolderAndRegistersNothing(t *testing.T) {
	w := newUploadWriters()
	interrupted := holder(t, w, "f_1")

	w.interrupt("f_1", 5*time.Second)
	select {
	case <-interrupted:
	default:
		t.Fatal("the holder was never interrupted")
	}
	// Nothing registered: the file is free for the PUT that follows.
	release, ok := w.take("f_1", func() { t.Error("nobody should be holding the file") }, time.Millisecond)
	if !ok {
		t.Fatal("the file was not free after interrupt")
	}
	release()
	// Interrupting a file nobody writes returns at once.
	w.interrupt("f_free", time.Hour)
}

func TestInterruptReturnsAfterItsWaitWhenTheHolderIsStuck(t *testing.T) {
	w := newUploadWriters()
	stuck, ok := w.take("f_1", func() {}, time.Millisecond)
	if !ok {
		t.Fatal("take on a free file failed")
	}
	defer stuck()

	start := time.Now()
	w.interrupt("f_1", 30*time.Millisecond)
	if waited := time.Since(start); waited < 30*time.Millisecond || waited > 5*time.Second {
		t.Fatalf("interrupt returned after %v, want its 30ms wait", waited)
	}
}

func TestAReleaseCalledAgainDoesNotDropTheNextWriter(t *testing.T) {
	w := newUploadWriters()
	first, ok := w.take("f_1", func() {}, time.Millisecond)
	if !ok {
		t.Fatal("first take failed")
	}
	first()
	second, ok := w.take("f_1", func() {}, time.Millisecond)
	if !ok {
		t.Fatal("second take failed")
	}
	defer second()

	first() // a stale second call

	if _, ok := w.take("f_1", func() {}, 20*time.Millisecond); ok {
		t.Fatal("the second writer's registration was dropped by the first one's stale release")
	}
}
