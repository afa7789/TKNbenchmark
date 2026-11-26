// Package server implements the notes HTTP API.
//
// routes.go is the single list of endpoints. Handlers are grouped by feature, one file each:
// health.go, notes.go (create, get), crud.go (replace, delete), list.go (list) and stats.go (stats, tags).
// respond.go holds the JSON request and response helpers shared by all of them.
package server

import (
	"log/slog"
	"net/http"
	"strings"

	"notes/internal/store"
)

// Server serves the notes API. It is an http.Handler.
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

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if _, pattern := s.mux.Handler(r); pattern == "" {
		// No route matches: the mux answers 404, or 405 with an Allow header, in plain text. Keep its
		// status and headers but give the body the same JSON shape as every other error.
		w = &routeErrorWriter{ResponseWriter: w, s: s}
	}
	s.mux.ServeHTTP(w, r)
}

// routeErrorWriter rewrites the mux's plain-text 404 and 405 responses as JSON error responses.
type routeErrorWriter struct {
	http.ResponseWriter
	s         *Server
	rewritten bool
}

func (w *routeErrorWriter) WriteHeader(status int) {
	if status != http.StatusNotFound && status != http.StatusMethodNotAllowed ||
		!strings.HasPrefix(w.Header().Get("Content-Type"), "text/plain") {
		w.ResponseWriter.WriteHeader(status)
		return
	}
	w.rewritten = true
	h := w.Header()
	h.Del("Content-Length")
	h.Del("X-Content-Type-Options")
	msg := "not found"
	if status == http.StatusMethodNotAllowed {
		msg = "method not allowed"
	}
	w.s.writeError(w.ResponseWriter, status, msg)
}

func (w *routeErrorWriter) Write(b []byte) (int, error) {
	if w.rewritten {
		return len(b), nil // drop the mux's plain-text body
	}
	return w.ResponseWriter.Write(b)
}

func (w *routeErrorWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }
