// Package api implements the HTTP interface of the notes service.
package api

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"notes/internal/store"
)

// Server serves the notes HTTP API.
type Server struct {
	store *store.Store
	log   *slog.Logger
}

// New returns a Server backed by st.
func New(st *store.Store, log *slog.Logger) *Server {
	return &Server{store: st, log: log}
}

// Handler returns the HTTP handler with all routes registered. Unknown paths
// get 404 and known paths with an unsupported method get 405; both are
// decided by http.ServeMux and answered with a JSON error body.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)

	// notes.go
	mux.HandleFunc("POST /notes", s.handleCreateNote)
	mux.HandleFunc("GET /notes/{id}", s.handleGetNote)

	// crud.go
	mux.HandleFunc("PUT /notes/{id}", s.handleUpdateNote)
	mux.HandleFunc("DELETE /notes/{id}", s.handleDeleteNote)

	// list.go
	mux.HandleFunc("GET /notes", s.handleListNotes)

	// stats.go
	mux.HandleFunc("GET /stats", s.handleStats)
	mux.HandleFunc("GET /tags", s.handleTags)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if h, pattern := mux.Handler(r); pattern == "" {
			// No route matched: the mux answers with a plain-text 404 or
			// 405 (or a path-cleaning redirect).
			h.ServeHTTP(&jsonErrorWriter{ResponseWriter: w}, r)
			return
		}
		mux.ServeHTTP(w, r)
	})
}

// jsonErrorWriter replaces the plain-text body of an error response written
// by http.Error with {"error": "<status text>"}, keeping the status code and
// headers such as Allow.
type jsonErrorWriter struct {
	http.ResponseWriter
	replaced bool
}

func (w *jsonErrorWriter) WriteHeader(code int) {
	if code < http.StatusBadRequest {
		w.ResponseWriter.WriteHeader(code)
		return
	}
	w.replaced = true
	body, _ := json.Marshal(errorBody{Error: strings.ToLower(http.StatusText(code))})
	h := w.Header()
	h.Del("X-Content-Type-Options")
	h.Set("Content-Type", "application/json")
	h.Set("Content-Length", strconv.Itoa(len(body)+1))
	w.ResponseWriter.WriteHeader(code)
	w.ResponseWriter.Write(append(body, '\n'))
}

func (w *jsonErrorWriter) Write(b []byte) (int, error) {
	if w.replaced {
		return len(b), nil // drop the original plain-text body
	}
	return w.ResponseWriter.Write(b)
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte("ok"))
}
