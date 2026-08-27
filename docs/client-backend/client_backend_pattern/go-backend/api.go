package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
)

type noteInput struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

func (in *noteInput) validate() error {
	in.Title = strings.TrimSpace(in.Title)
	if in.Title == "" || len(in.Title) > 200 {
		return errors.New("title must be 1..200 characters")
	}
	if len(in.Body) > 100_000 {
		return errors.New("body too large")
	}
	return nil
}

func addRoutes(mux *http.ServeMux, store *Store, hub *Hub) {
	mux.HandleFunc("GET /api/notes", func(w http.ResponseWriter, r *http.Request) {
		notes, err := store.ListNotes(r.Context())
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, notes)
	})

	mux.HandleFunc("GET /api/notes/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, ok := pathID(w, r)
		if !ok {
			return
		}
		note, err := store.GetNote(r.Context(), id)
		if err != nil {
			notFoundOr500(w, err)
			return
		}
		writeJSON(w, http.StatusOK, note)
	})

	mux.HandleFunc("POST /api/notes", func(w http.ResponseWriter, r *http.Request) {
		var in noteInput
		if !readJSON(w, r, &in) {
			return
		}
		if err := in.validate(); err != nil {
			badRequest(w, err.Error())
			return
		}
		note, err := store.CreateNote(r.Context(), in.Title, in.Body)
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, note)
	})

	mux.HandleFunc("PUT /api/notes/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, ok := pathID(w, r)
		if !ok {
			return
		}
		var in noteInput
		if !readJSON(w, r, &in) {
			return
		}
		if err := in.validate(); err != nil {
			badRequest(w, err.Error())
			return
		}
		note, err := store.UpdateNote(r.Context(), id, in.Title, in.Body)
		if err != nil {
			notFoundOr500(w, err)
			return
		}
		writeJSON(w, http.StatusOK, note)
	})

	mux.HandleFunc("DELETE /api/notes/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, ok := pathID(w, r)
		if !ok {
			return
		}
		if err := store.DeleteNote(r.Context(), id); err != nil {
			notFoundOr500(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})

	// REST fallback for the outbox: lets clients poll or catch up without
	// a socket. Same data the WebSocket replays.
	mux.HandleFunc("GET /api/events", func(w http.ResponseWriter, r *http.Request) {
		since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
		evs, err := store.EventsSince(r.Context(), since)
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, evs)
	})

	mux.HandleFunc("GET /ws", handleWS(store, hub))
}

// ---- helpers ----

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		badRequest(w, "invalid id")
		return 0, false
	}
	return id, true
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		badRequest(w, "invalid JSON: "+err.Error())
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("write response: %v", err)
	}
}

func badRequest(w http.ResponseWriter, msg string) {
	writeJSON(w, http.StatusBadRequest, map[string]string{"error": msg})
}

func notFoundOr500(w http.ResponseWriter, err error) {
	if errors.Is(err, ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
		return
	}
	serverError(w, err)
}

func serverError(w http.ResponseWriter, err error) {
	log.Printf("internal error: %v", err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
}
