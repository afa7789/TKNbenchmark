// Package httpapi exposes the notes store over HTTP.
//
// Files are split by feature so they can be developed independently:
//
//	server.go   Server, routing table and error rewriting for unmatched routes
//	respond.go  shared request/response helpers
//	notes.go    POST /notes, GET /notes/{id}
//	crud.go     PUT /notes/{id}, DELETE /notes/{id}
//	list.go     GET /notes
//	stats.go    GET /stats, GET /tags
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"notes/internal/store"
)

// Server routes HTTP requests to the notes store. It is safe for concurrent use.
type Server struct {
	store *store.Store
	log   *slog.Logger
	mux   *http.ServeMux
}

// New returns a Server backed by st that logs unexpected errors to log.
func New(st *store.Store, log *slog.Logger) *Server {
	s := &Server{store: st, log: log, mux: http.NewServeMux()}
	s.routes()
	return s
}

// routes is the complete routing table. Handlers live in their feature files.
// A path registered for some methods automatically answers 405 for the others.
func (s *Server) routes() {
	s.mux.HandleFunc("GET /health", s.handleHealth)

	s.mux.HandleFunc("POST /notes", s.handleCreate)
	s.mux.HandleFunc("GET /notes/{id}", s.handleGet)

	s.mux.HandleFunc("PUT /notes/{id}", s.handleUpdate)
	s.mux.HandleFunc("DELETE /notes/{id}", s.handleDelete)

	s.mux.HandleFunc("GET /notes", s.handleList)

	s.mux.HandleFunc("GET /stats", s.handleStats)
	s.mux.HandleFunc("GET /tags", s.handleTags)
}

// ServeHTTP implements http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if _, pattern := s.mux.Handler(r); pattern == "" {
		// No route matched: the mux answers 404, 405 or a redirect in plain
		// text. Keep its status and headers (such as Allow) but send the
		// error body as JSON like every other error.
		w = &jsonErrorWriter{ResponseWriter: w}
	}
	s.mux.ServeHTTP(w, r)
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte("ok"))
}

// jsonErrorWriter replaces the body of error responses with {"error": "..."}.
type jsonErrorWriter struct {
	http.ResponseWriter
	discard bool
}

func (w *jsonErrorWriter) WriteHeader(code int) {
	if code < http.StatusBadRequest {
		w.ResponseWriter.WriteHeader(code)
		return
	}
	w.discard = true
	w.Header().Set("Content-Type", "application/json")
	w.ResponseWriter.WriteHeader(code)
	_ = json.NewEncoder(w.ResponseWriter).Encode(errorBody{Error: strings.ToLower(http.StatusText(code))})
}

func (w *jsonErrorWriter) Write(b []byte) (int, error) {
	if w.discard {
		return len(b), nil
	}
	return w.ResponseWriter.Write(b)
}
