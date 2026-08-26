package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080",
		"listen address (keep on loopback; TLS is terminated by Caddy in front)")
	dbPath := flag.String("db", "app.db", "SQLite database file")
	flag.Parse()

	readDB, writeDB, err := openDB(*dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer readDB.Close()
	defer writeDB.Close()

	if err := migrate(writeDB); err != nil {
		log.Fatal(err)
	}

	// The hub gets its own lifetime, cancelled only AFTER the HTTP server
	// has drained, so no handler can block on a stopped hub.
	hubCtx, stopHub := context.WithCancel(context.Background())
	defer stopHub()
	hub := newHub()
	go hub.run(hubCtx)

	store := &Store{read: readDB, write: writeDB, hub: hub}

	mux := http.NewServeMux()
	addRoutes(mux, store, hub)

	srv := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	sigCtx, stop := signal.NotifyContext(context.Background(),
		syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Printf("listening on http://%s (db: %s)", *addr, *dbPath)
		if err := srv.ListenAndServe(); err != nil &&
			!errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()

	<-sigCtx.Done()
	log.Println("shutting down")

	shCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	stopHub() // now safe: all handlers have returned
}
