package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"kvhttp/internal/store"
)

// maxValueBytes is the largest value accepted by PUT /kv/<key>.
const maxValueBytes = 1 << 20

const kvPrefix = "/kv/"

// server routes HTTP requests to the key-value store.
type server struct {
	store *store.Store
}

func newServer(s *store.Store) *server {
	return &server{store: s}
}

// ServeHTTP dispatches on the raw (still-escaped) request path so that
// percent-encoded characters are never accepted as part of a key.
func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// One request per connection; any unread body is discarded.
	w.Header().Set("Connection", "close")

	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		send(w, http.StatusOK, "text/plain", []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		s.handleList(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			send(w, http.StatusBadRequest, "", nil)
			return
		}
		s.handleKey(w, r, key)
	default:
		send(w, http.StatusNotFound, "", nil)
	}
}

func (s *server) handleList(w http.ResponseWriter) {
	body, err := json.Marshal(s.store.Keys())
	if err != nil {
		log.Printf("encode keys: %v", err)
		send(w, http.StatusInternalServerError, "", nil)
		return
	}
	send(w, http.StatusOK, "application/json", body)
}

func (s *server) handleKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		value, ok := s.store.Get(key)
		if !ok {
			send(w, http.StatusNotFound, "", nil)
			return
		}
		send(w, http.StatusOK, "application/octet-stream", value)
	case http.MethodPut:
		value, err := readBody(w, r, maxValueBytes)
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				send(w, http.StatusRequestEntityTooLarge, "", nil)
			} else {
				send(w, http.StatusBadRequest, "", nil)
			}
			return
		}
		status := http.StatusOK
		if s.store.Put(key, value) {
			status = http.StatusCreated
		}
		send(w, status, "", nil)
	case http.MethodDelete:
		status := http.StatusNotFound
		if s.store.Delete(key) {
			status = http.StatusNoContent
		}
		send(w, status, "", nil)
	default:
		methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
	}
}

// readBody reads the full request body, failing with *http.MaxBytesError if
// it exceeds limit bytes.
func readBody(w http.ResponseWriter, r *http.Request, limit int64) ([]byte, error) {
	if r.ContentLength > limit {
		return nil, &http.MaxBytesError{Limit: limit}
	}
	return io.ReadAll(http.MaxBytesReader(w, r.Body, limit))
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

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	send(w, http.StatusMethodNotAllowed, "", nil)
}

// send writes a complete response with an explicit Content-Length.
func send(w http.ResponseWriter, status int, contentType string, body []byte) {
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
			log.Printf("write response: %v", err)
		}
	}
}
