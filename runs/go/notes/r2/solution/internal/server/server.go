// Package server exposes the notes store over HTTP.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"maps"
	"net/http"
	"slices"
	"strconv"
	"strings"

	"notes/internal/notes"
)

const (
	maxBodyBytes = 16 << 20
	defaultLimit = 100
	maxLimit     = 100
)

// Server serves the notes HTTP API.
type Server struct {
	store *notes.Store
	log   *slog.Logger
	mux   *http.ServeMux
}

// New returns an http.Handler for the notes API backed by store.
func New(store *notes.Store, log *slog.Logger) *Server {
	s := &Server{store: store, log: log, mux: http.NewServeMux()}
	s.route("/health", map[string]http.HandlerFunc{http.MethodGet: s.health})
	s.route("/notes", map[string]http.HandlerFunc{
		http.MethodGet:  s.listNotes,
		http.MethodPost: s.createNote,
	})
	s.route("/notes/{id}", map[string]http.HandlerFunc{
		http.MethodGet:    s.getNote,
		http.MethodPut:    s.updateNote,
		http.MethodDelete: s.deleteNote,
	})
	s.route("/stats", map[string]http.HandlerFunc{http.MethodGet: s.stats})
	s.route("/tags", map[string]http.HandlerFunc{http.MethodGet: s.tags})
	s.mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "not found")
	})
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) { s.mux.ServeHTTP(w, r) }

// route registers per-method handlers for an exact path, answering other methods with 405
// and a JSON body (ServeMux's built-in 405 is plain text).
func (s *Server) route(pattern string, methods map[string]http.HandlerFunc) {
	allow := strings.Join(slices.Sorted(maps.Keys(methods)), ", ")
	if get, ok := methods[http.MethodGet]; ok {
		methods[http.MethodHead] = get
	}
	s.mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		h, ok := methods[r.Method]
		if !ok {
			w.Header().Set("Allow", allow)
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}
		h(w, r)
	})
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	io.WriteString(w, "ok")
}

func (s *Server) createNote(w http.ResponseWriter, r *http.Request) {
	in, ok := s.readInput(w, r)
	if !ok {
		return
	}
	n, err := s.store.Create(r.Context(), in)
	if err != nil {
		s.internalError(w, err)
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
	if s.storeError(w, err) {
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) updateNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(w, r)
	if !ok {
		return
	}
	in, ok := s.readInput(w, r)
	if !ok {
		return
	}
	n, err := s.store.Update(r.Context(), id, in)
	if s.storeError(w, err) {
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) deleteNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(w, r)
	if !ok {
		return
	}
	if s.storeError(w, s.store.Delete(r.Context(), id)) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) listNotes(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f := notes.Filter{Tag: q.Get("tag"), Query: q.Get("q"), Limit: defaultLimit}
	if q.Has("limit") {
		n, err := strconv.Atoi(q.Get("limit"))
		if err != nil || n < 1 || n > maxLimit {
			writeError(w, http.StatusBadRequest, "limit must be an integer from 1 to 100")
			return
		}
		f.Limit = n
	}
	if q.Has("after") {
		n, err := strconv.ParseInt(q.Get("after"), 10, 64)
		if err != nil {
			writeError(w, http.StatusBadRequest, "after must be an integer")
			return
		}
		f.After = n
	}
	list, err := s.store.List(r.Context(), f)
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"notes": list})
}

func (s *Server) stats(w http.ResponseWriter, r *http.Request) {
	count, err := s.store.Count(r.Context())
	if err != nil {
		s.internalError(w, err)
		return
	}
	counts, err := s.store.TagCounts(r.Context())
	if err != nil {
		s.internalError(w, err)
		return
	}
	tags := make(map[string]int64, len(counts))
	for _, tc := range counts {
		tags[tc.Tag] = tc.Count
	}
	writeJSON(w, http.StatusOK, map[string]any{"notes": count, "tags": tags})
}

func (s *Server) tags(w http.ResponseWriter, r *http.Request) {
	counts, err := s.store.TagCounts(r.Context())
	if err != nil {
		s.internalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tags": counts})
}

// readInput reads and validates a note payload, writing a 400 response on failure.
func (s *Server) readInput(w http.ResponseWriter, r *http.Request) (notes.Input, bool) {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeError(w, http.StatusRequestEntityTooLarge, "request body too large")
		} else {
			writeError(w, http.StatusBadRequest, "could not read request body")
		}
		return notes.Input{}, false
	}
	in, err := notes.ParseInput(data)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return notes.Input{}, false
	}
	return in, true
}

// noteID parses the {id} path segment; anything but a positive decimal integer is a 404.
func noteID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	raw := r.PathValue("id")
	for i := 0; i < len(raw); i++ {
		if raw[i] < '0' || raw[i] > '9' {
			raw = ""
			break
		}
	}
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || id < 1 {
		writeError(w, http.StatusNotFound, "note not found")
		return 0, false
	}
	return id, true
}

// storeError writes a response for a non-nil store error and reports whether it did.
func (s *Server) storeError(w http.ResponseWriter, err error) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, notes.ErrNotFound):
		writeError(w, http.StatusNotFound, "note not found")
	default:
		s.internalError(w, err)
	}
	return true
}

func (s *Server) internalError(w http.ResponseWriter, err error) {
	s.log.Error("request failed", "err", err)
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
	w.Write(append(data, '\n'))
}
