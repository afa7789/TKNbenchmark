package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
)

// MaxValueBytes is the largest value accepted by PUT /kv/<key>.
const MaxValueBytes = 1 << 20

const maxKeyLen = 64

// Server routes HTTP requests to a Store.
type Server struct {
	store *Store
}

// NewServer returns an http.Handler serving the key-value API backed by store.
func NewServer(store *Store) *Server {
	return &Server{store: store}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Route on the raw request target so that escapes like %2F or dot
	// segments are treated literally rather than decoded or cleaned.
	path := requestPath(r)

	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		send(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))

	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		s.list(w)

	case strings.HasPrefix(path, "/kv/"):
		key := strings.TrimPrefix(path, "/kv/")
		if !validKey(key) {
			sendError(w, http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			s.get(w, key)
		case http.MethodPut:
			s.put(w, r, key)
		case http.MethodDelete:
			s.delete(w, key)
		default:
			methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
		}

	default:
		sendError(w, http.StatusNotFound)
	}
}

func (s *Server) list(w http.ResponseWriter) {
	body, err := json.Marshal(s.store.Keys())
	if err != nil {
		log.Printf("encode keys: %v", err)
		sendError(w, http.StatusInternalServerError)
		return
	}
	send(w, http.StatusOK, "application/json", body)
}

func (s *Server) get(w http.ResponseWriter, key string) {
	value, ok := s.store.Get(key)
	if !ok {
		sendError(w, http.StatusNotFound)
		return
	}
	send(w, http.StatusOK, "application/octet-stream", value)
}

func (s *Server) put(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > MaxValueBytes {
		tooLarge(w)
		return
	}
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueBytes))
	if err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			tooLarge(w)
			return
		}
		sendError(w, http.StatusBadRequest)
		return
	}
	status := http.StatusCreated
	if s.store.Put(key, value) {
		status = http.StatusOK
	}
	send(w, status, "", nil)
}

func (s *Server) delete(w http.ResponseWriter, key string) {
	if !s.store.Delete(key) {
		sendError(w, http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// requestPath returns the undecoded path of the request target.
func requestPath(r *http.Request) string {
	path, _, _ := strings.Cut(r.RequestURI, "?")
	if !strings.HasPrefix(path, "/") {
		// Absolute-form or asterisk-form target.
		path = r.URL.EscapedPath()
	}
	return path
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

// send writes a complete response with an explicit Content-Length.
// A Content-Type is set only when the body is non-empty.
func send(w http.ResponseWriter, status int, contentType string, body []byte) {
	h := w.Header()
	if len(body) > 0 && contentType != "" {
		h.Set("Content-Type", contentType)
	}
	h.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if len(body) > 0 {
		_, _ = w.Write(body)
	}
}

func sendError(w http.ResponseWriter, status int) {
	send(w, status, "text/plain; charset=utf-8", []byte(http.StatusText(status)))
}

func methodNotAllowed(w http.ResponseWriter, methods ...string) {
	w.Header().Set("Allow", strings.Join(methods, ", "))
	sendError(w, http.StatusMethodNotAllowed)
}

func tooLarge(w http.ResponseWriter) {
	w.Header().Set("Connection", "close")
	sendError(w, http.StatusRequestEntityTooLarge)
}
