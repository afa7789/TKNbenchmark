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

const (
	maxValueSize = 1 << 20 // 1 MiB
	maxKeyLen    = 64
	kvPrefix     = "/kv/"
)

// Server routes HTTP requests to a Store.
type Server struct {
	store *Store
}

// NewServer returns a Server backed by store.
func NewServer(store *Store) *Server {
	return &Server{store: store}
}

// ServeHTTP implements http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.ContentLength > maxValueSize {
		http.Error(w, "", http.StatusRequestEntityTooLarge)
		return
	}

	// Route on the raw request target so percent-escapes are not decoded
	// into characters that would otherwise be rejected in a key.
	path, _, _ := strings.Cut(r.RequestURI, "?")

	switch {
	case path == "/health":
		if !allowMethods(w, r, http.MethodGet) {
			return
		}
		writeBody(w, http.StatusOK, "text/plain", []byte("ok"))
	case path == "/kv":
		if !allowMethods(w, r, http.MethodGet) {
			return
		}
		s.handleList(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			writeStatus(w, http.StatusBadRequest)
			return
		}
		s.handleKey(w, r, key)
	default:
		writeStatus(w, http.StatusNotFound)
	}
}

func (s *Server) handleList(w http.ResponseWriter) {
	body, err := json.Marshal(s.store.Keys())
	if err != nil {
		slog.Error("encode key list", "err", err)
		writeStatus(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (s *Server) handleKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		value, ok := s.store.Get(key)
		if !ok {
			writeStatus(w, http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", value)
	case http.MethodPut:
		value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxValueSize))
		if err != nil {
			if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
				writeStatus(w, http.StatusRequestEntityTooLarge)
			} else {
				writeStatus(w, http.StatusBadRequest)
			}
			return
		}
		if s.store.Put(key, value) {
			writeStatus(w, http.StatusCreated)
		} else {
			writeStatus(w, http.StatusOK)
		}
	case http.MethodDelete:
		if s.store.Delete(key) {
			writeStatus(w, http.StatusNoContent)
		} else {
			writeStatus(w, http.StatusNotFound)
		}
	default:
		w.Header().Set("Allow", "GET, PUT, DELETE")
		writeStatus(w, http.StatusMethodNotAllowed)
	}
}

// allowMethods writes a 405 and returns false unless r uses one of methods.
func allowMethods(w http.ResponseWriter, r *http.Request, methods ...string) bool {
	for _, m := range methods {
		if r.Method == m {
			return true
		}
	}
	w.Header().Set("Allow", strings.Join(methods, ", "))
	writeStatus(w, http.StatusMethodNotAllowed)
	return false
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > maxKeyLen {
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

func writeStatus(w http.ResponseWriter, status int) {
	writeBody(w, status, "", nil)
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	h := w.Header()
	if contentType != "" {
		h.Set("Content-Type", contentType)
	}
	if status != http.StatusNoContent {
		h.Set("Content-Length", strconv.Itoa(len(body)))
	}
	w.WriteHeader(status)
	if len(body) > 0 {
		if _, err := w.Write(body); err != nil {
			slog.Debug("write response", "err", err)
		}
	}
}
