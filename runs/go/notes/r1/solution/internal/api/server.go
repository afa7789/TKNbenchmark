// Package api implements the HTTP interface of the notes service.
package api

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"notes/internal/store"
)

const (
	maxBodyBytes = 32 << 20
	defaultLimit = 100
	maxLimit     = 100
)

// Server routes HTTP requests to the note store.
type Server struct {
	store *store.Store
	log   *slog.Logger
}

// New returns an http.Handler serving the notes API.
func New(st *store.Store, log *slog.Logger) *Server {
	return &Server{store: st, log: log}
}

// ServeHTTP dispatches by path, answering 404 for unknown paths and 405 for unsupported methods.
// Routing is done by hand so that every error, including 404 and 405, carries a JSON body.
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
	case strings.HasPrefix(path, "/notes/"):
		id, ok := parsePositiveID(strings.TrimPrefix(path, "/notes/"))
		if !ok {
			writeError(w, http.StatusNotFound, "note not found")
			return
		}
		s.route(w, r, map[string]http.HandlerFunc{
			http.MethodGet:    func(w http.ResponseWriter, r *http.Request) { s.getNote(w, r, id) },
			http.MethodPut:    func(w http.ResponseWriter, r *http.Request) { s.updateNote(w, r, id) },
			http.MethodDelete: func(w http.ResponseWriter, r *http.Request) { s.deleteNote(w, r, id) },
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
	if h, ok := methods[r.Method]; ok {
		h(w, r)
		return
	}
	if r.Method == http.MethodHead {
		if h, ok := methods[http.MethodGet]; ok {
			h(w, r)
			return
		}
	}
	allow := make([]string, 0, len(methods))
	for _, m := range []string{http.MethodGet, http.MethodPost, http.MethodPut, http.MethodDelete} {
		if _, ok := methods[m]; ok {
			allow = append(allow, m)
		}
	}
	w.Header().Set("Allow", strings.Join(allow, ", "))
	writeError(w, http.StatusMethodNotAllowed, "method not allowed")
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
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, n)
}

func (s *Server) getNote(w http.ResponseWriter, r *http.Request, id int64) {
	n, err := s.store.Get(r.Context(), id)
	if s.storeError(w, err) {
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) updateNote(w http.ResponseWriter, r *http.Request, id int64) {
	in, ok := s.readNoteInput(w, r)
	if !ok {
		return
	}
	n, err := s.store.Update(r.Context(), id, in.Title, in.Body, in.Tags)
	if s.storeError(w, err) {
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) deleteNote(w http.ResponseWriter, r *http.Request, id int64) {
	if s.storeError(w, s.store.Delete(r.Context(), id)) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) listNotes(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f := store.ListFilter{Limit: defaultLimit}
	if q.Has("tag") {
		f.Tag, f.HasTag = q.Get("tag"), true
	}
	f.Query = q.Get("q")
	if q.Has("after") {
		after, ok := parseInt(q.Get("after"))
		if !ok {
			writeError(w, http.StatusBadRequest, "after must be an integer")
			return
		}
		f.After, f.HasAfter = after, true
	}
	if q.Has("limit") {
		limit, ok := parseInt(q.Get("limit"))
		if !ok || limit < 1 || limit > maxLimit {
			writeError(w, http.StatusBadRequest, "limit must be an integer from 1 to 100")
			return
		}
		f.Limit = int(limit)
	}
	notes, err := s.store.List(r.Context(), f)
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"notes": notes})
}

func (s *Server) stats(w http.ResponseWriter, r *http.Request) {
	count, tags, err := s.store.Stats(r.Context())
	if err != nil {
		s.internalError(w, err)
		return
	}
	byTag := make(map[string]int64, len(tags))
	for _, t := range tags {
		byTag[t.Tag] = t.Count
	}
	writeJSON(w, http.StatusOK, map[string]any{"notes": count, "tags": byTag})
}

func (s *Server) tags(w http.ResponseWriter, r *http.Request) {
	tags, err := s.store.Tags(r.Context())
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tags": tags})
}

// readNoteInput reads and validates the request body, writing a 400 response on failure.
func (s *Server) readNoteInput(w http.ResponseWriter, r *http.Request) (noteInput, bool) {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, http.StatusBadRequest, "request body too large")
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

// storeError writes a response for a non-nil store error and reports whether it did.
func (s *Server) storeError(w http.ResponseWriter, err error) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "note not found")
	default:
		s.internalError(w, err)
	}
	return true
}

func (s *Server) internalError(w http.ResponseWriter, err error) {
	s.log.Error("request failed", "err", err)
	writeError(w, http.StatusInternalServerError, "internal error")
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(data)
}
