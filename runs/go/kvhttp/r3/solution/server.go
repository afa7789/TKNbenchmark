package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
)

const maxValueSize = 1 << 20 // 1 MiB

// Server routes HTTP requests to a Store.
type Server struct {
	store *Store
}

// NewServer returns an http.Handler serving the kvhttp API backed by store.
func NewServer(store *Store) *Server {
	return &Server{store: store}
}

// ServeHTTP implements http.Handler. Routing is done by hand rather than with
// http.ServeMux so that paths are matched exactly, without cleaning or redirects.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	switch {
	case path == "/health":
		s.handleHealth(w, r)
	case path == "/kv":
		s.handleList(w, r)
	case strings.HasPrefix(path, "/kv/"):
		key := path[len("/kv/"):]
		if !validKey(key) {
			writeError(w, http.StatusBadRequest)
			return
		}
		s.handleKey(w, r, key)
	default:
		writeError(w, http.StatusNotFound)
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
}

func (s *Server) handleList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	body, err := json.Marshal(s.store.Keys())
	if err != nil {
		writeError(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (s *Server) handleKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		v, ok := s.store.Get(key)
		if !ok {
			writeError(w, http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", v)
	case http.MethodPut:
		value, err := readValue(w, r)
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				writeError(w, http.StatusRequestEntityTooLarge)
			} else {
				writeError(w, http.StatusBadRequest)
			}
			return
		}
		status := http.StatusOK
		if s.store.Put(key, value) {
			status = http.StatusCreated
		}
		writeEmpty(w, status)
	case http.MethodDelete:
		if !s.store.Delete(key) {
			writeError(w, http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
	}
}

// readValue reads the request body, enforcing the maximum value size.
func readValue(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	if r.ContentLength > maxValueSize {
		return nil, &http.MaxBytesError{Limit: maxValueSize}
	}
	body := http.MaxBytesReader(w, r.Body, maxValueSize)
	if r.ContentLength >= 0 {
		buf := make([]byte, r.ContentLength)
		if _, err := io.ReadFull(body, buf); err != nil {
			return nil, err
		}
		return buf, nil
	}
	return io.ReadAll(body)
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > 64 {
		return false
	}
	for i := 0; i < len(key); i++ {
		c := key[i]
		switch {
		case 'a' <= c && c <= 'z', 'A' <= c && c <= 'Z', '0' <= c && c <= '9', c == '_', c == '-':
		default:
			return false
		}
	}
	return true
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	h := w.Header()
	h.Set("Content-Type", contentType)
	h.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func writeEmpty(w http.ResponseWriter, status int) {
	w.Header().Set("Content-Length", "0")
	w.WriteHeader(status)
}

func writeError(w http.ResponseWriter, status int) {
	writeBody(w, status, "text/plain; charset=utf-8", []byte(http.StatusText(status)+"\n"))
}

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	writeError(w, http.StatusMethodNotAllowed)
}
