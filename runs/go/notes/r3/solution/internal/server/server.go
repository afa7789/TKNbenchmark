// Package server implements the notes HTTP API.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"slices"
	"strings"

	"notes/internal/store"
)

const (
	maxBodyBytes = 16 << 20
	maxLimit     = 100
)

// Server serves the notes API backed by a Store.
type Server struct {
	store *store.Store
	log   *slog.Logger
}

// New returns an http.Handler serving the notes API.
func New(st *store.Store, log *slog.Logger) *Server {
	return &Server{store: st, log: log}
}

// ServeHTTP routes requests. Routing is done by hand so that unknown paths,
// unsupported methods and malformed ids all get JSON error bodies.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	switch {
	case path == "/health":
		s.route(w, r, map[string]http.HandlerFunc{http.MethodGet: s.health})
	case path == "/notes":
		s.route(w, r, map[string]http.HandlerFunc{
			http.MethodGet:  s.listNotes,
			http.MethodPost: s.createNote,
		})
	case strings.HasPrefix(path, "/notes/") && !strings.Contains(path[len("/notes/"):], "/"):
		s.route(w, r, map[string]http.HandlerFunc{
			http.MethodGet:    s.getNote,
			http.MethodPut:    s.updateNote,
			http.MethodDelete: s.deleteNote,
		})
	case path == "/stats":
		s.route(w, r, map[string]http.HandlerFunc{http.MethodGet: s.stats})
	case path == "/tags":
		s.route(w, r, map[string]http.HandlerFunc{http.MethodGet: s.tags})
	default:
		writeError(w, http.StatusNotFound, "not found")
	}
}

func (s *Server) route(w http.ResponseWriter, r *http.Request, methods map[string]http.HandlerFunc) {
	h, ok := methods[r.Method]
	if !ok {
		allowed := make([]string, 0, len(methods))
		for m := range methods {
			allowed = append(allowed, m)
		}
		slices.Sort(allowed)
		w.Header().Set("Allow", strings.Join(allowed, ", "))
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	h(w, r)
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = io.WriteString(w, "ok")
}

func (s *Server) createNote(w http.ResponseWriter, r *http.Request) {
	in, ok := s.readNoteInput(w, r)
	if !ok {
		return
	}
	n, err := s.store.Create(r.Context(), in.Title, in.Body, in.Tags)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, n)
}

func (s *Server) getNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(w, r)
	if !ok {
		return
	}
	n, err := s.store.Get(r.Context(), id)
	if err != nil {
		s.storeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) updateNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(w, r)
	if !ok {
		return
	}
	in, ok := s.readNoteInput(w, r)
	if !ok {
		return
	}
	n, err := s.store.Update(r.Context(), id, in.Title, in.Body, in.Tags)
	if err != nil {
		s.storeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) deleteNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(w, r)
	if !ok {
		return
	}
	if err := s.store.Delete(r.Context(), id); err != nil {
		s.storeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) listNotes(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f := store.ListFilter{
		Tag:   q.Get("tag"),
		Query: q.Get("q"),
		Limit: maxLimit,
	}
	if q.Has("limit") {
		n, ok := parseInt(q.Get("limit"))
		if !ok || n < 1 || n > maxLimit {
			writeError(w, http.StatusBadRequest, "limit must be an integer from 1 to 100")
			return
		}
		f.Limit = int(n)
	}
	if q.Has("after") {
		n, ok := parseInt(q.Get("after"))
		if !ok {
			writeError(w, http.StatusBadRequest, "after must be an integer")
			return
		}
		f.After = n
	}
	notes, err := s.store.List(r.Context(), f)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"notes": notes})
}

func (s *Server) stats(w http.ResponseWriter, r *http.Request) {
	total, counts, err := s.store.Stats(r.Context())
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	tags := make(map[string]int64, len(counts))
	for _, tc := range counts {
		tags[tc.Tag] = tc.Count
	}
	writeJSON(w, http.StatusOK, map[string]any{"notes": total, "tags": tags})
}

func (s *Server) tags(w http.ResponseWriter, r *http.Request) {
	counts, err := s.store.TagCounts(r.Context())
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tags": counts})
}

func (s *Server) readNoteInput(w http.ResponseWriter, r *http.Request) (noteInput, bool) {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, http.StatusRequestEntityTooLarge, "request body too large")
		} else {
			writeError(w, http.StatusBadRequest, "could not read request body")
		}
		return noteInput{}, false
	}
	in, err := parseNoteInput(data)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return noteInput{}, false
	}
	return in, true
}

func noteID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, ok := parsePositiveID(strings.TrimPrefix(r.URL.Path, "/notes/"))
	if !ok {
		writeError(w, http.StatusNotFound, "note not found")
	}
	return id, ok
}

func (s *Server) storeError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "note not found")
		return
	}
	s.internalError(w, r, err)
}

func (s *Server) internalError(w http.ResponseWriter, r *http.Request, err error) {
	s.log.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
	writeError(w, http.StatusInternalServerError, "internal server error")
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(append(data, '\n'))
}
