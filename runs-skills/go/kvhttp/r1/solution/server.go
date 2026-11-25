package main

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
)

// maxValueSize is the largest value accepted by PUT /kv/<key>.
const maxValueSize = 1 << 20

// Server routes HTTP requests to a Store.
//
// Routing is done by hand rather than with http.ServeMux so that paths are
// never cleaned or redirected: the spec requires exact status codes for
// malformed keys such as "/kv/a/b" or "/kv/".
type Server struct {
	store *Store
}

// NewServer returns a Server backed by store.
func NewServer(store *Store) *Server {
	return &Server{store: store}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	switch {
	case path == "/health":
		if !allow(w, r, http.MethodGet) {
			return
		}
		writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
	case path == "/kv":
		if !allow(w, r, http.MethodGet) {
			return
		}
		s.handleList(w)
	case strings.HasPrefix(path, "/kv/"):
		if !allow(w, r, http.MethodGet, http.MethodPut, http.MethodDelete) {
			return
		}
		key := strings.TrimPrefix(path, "/kv/")
		if !validKey(key) {
			writeError(w, http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			s.handleGet(w, key)
		case http.MethodPut:
			s.handlePut(w, r, key)
		case http.MethodDelete:
			s.handleDelete(w, key)
		}
	default:
		writeError(w, http.StatusNotFound)
	}
}

func (s *Server) handleList(w http.ResponseWriter) {
	body, err := json.Marshal(s.store.Keys())
	if err != nil {
		slog.Error("marshal keys", "err", err)
		writeError(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (s *Server) handleGet(w http.ResponseWriter, key string) {
	v, ok := s.store.Get(key)
	if !ok {
		writeError(w, http.StatusNotFound)
		return
	}
	writeBody(w, http.StatusOK, "application/octet-stream", v)
}

func (s *Server) handlePut(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > maxValueSize {
		writeError(w, http.StatusRequestEntityTooLarge)
		return
	}
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxValueSize))
	if err != nil {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			writeError(w, http.StatusRequestEntityTooLarge)
			return
		}
		writeError(w, http.StatusBadRequest)
		return
	}
	status := http.StatusOK
	if s.store.Put(key, value) {
		status = http.StatusCreated
	}
	writeBody(w, status, "", nil)
}

func (s *Server) handleDelete(w http.ResponseWriter, key string) {
	if !s.store.Delete(key) {
		writeError(w, http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// allow reports whether r.Method is one of methods. If not, it writes a 405
// response with an Allow header and returns false.
func allow(w http.ResponseWriter, r *http.Request, methods ...string) bool {
	for _, m := range methods {
		if r.Method == m {
			return true
		}
	}
	w.Header().Set("Allow", strings.Join(methods, ", "))
	writeError(w, http.StatusMethodNotAllowed)
	return false
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > 64 {
		return false
	}
	for i := range len(key) {
		c := key[i]
		switch {
		case 'a' <= c && c <= 'z', 'A' <= c && c <= 'Z', '0' <= c && c <= '9', c == '_', c == '-':
		default:
			return false
		}
	}
	return true
}

func writeError(w http.ResponseWriter, status int) {
	writeBody(w, status, "text/plain; charset=utf-8", []byte(http.StatusText(status)))
}

// writeBody writes a complete response with an explicit Content-Length.
func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	h := w.Header()
	if contentType != "" {
		h.Set("Content-Type", contentType)
	}
	h.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if len(body) > 0 {
		if _, err := w.Write(body); err != nil {
			slog.Debug("write response", "err", err)
		}
	}
}
