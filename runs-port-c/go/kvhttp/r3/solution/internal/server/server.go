// Package server exposes a store.Store over HTTP.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"kvhttp/internal/store"
)

const (
	// MaxKeyLen is the maximum key length in bytes.
	MaxKeyLen = 64
	// MaxValueLen is the maximum value size in bytes.
	MaxValueLen = 1 << 20

	kvPrefix = "/kv/"
)

// Handler routes requests to the key-value store.
//
// It deliberately does not use http.ServeMux: the mux cleans and redirects
// paths, whereas this API must reject malformed keys with 400.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.ContentLength > MaxValueLen {
		w.Header().Set("Connection", "close")
		writeEmpty(w, http.StatusRequestEntityTooLarge)
		return
	}

	// Use the path as sent so that percent-escapes are never decoded into
	// otherwise valid key characters.
	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		writeBody(w, http.StatusOK, "text/plain", []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		h.list(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			writeEmpty(w, http.StatusBadRequest)
			return
		}
		h.key(w, r, key)
	default:
		writeEmpty(w, http.StatusNotFound)
	}
}

func (h *Handler) list(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		writeEmpty(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) key(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		val, ok := h.store.Get(key)
		if !ok {
			writeEmpty(w, http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", val)
	case http.MethodPut:
		val, err := readBody(w, r)
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				writeEmpty(w, http.StatusRequestEntityTooLarge)
			} else {
				writeEmpty(w, http.StatusBadRequest)
			}
			return
		}
		if h.store.Put(key, val) {
			writeEmpty(w, http.StatusCreated)
		} else {
			writeEmpty(w, http.StatusOK)
		}
	case http.MethodDelete:
		if h.store.Delete(key) {
			w.WriteHeader(http.StatusNoContent)
		} else {
			writeEmpty(w, http.StatusNotFound)
		}
	default:
		methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
	}
}

// readBody reads the full request body, enforcing MaxValueLen.
func readBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	body := http.MaxBytesReader(w, r.Body, MaxValueLen)
	if r.ContentLength >= 0 {
		buf := make([]byte, r.ContentLength)
		if _, err := io.ReadFull(body, buf); err != nil {
			return nil, err
		}
		return buf, nil
	}
	return io.ReadAll(body)
}

// validKey reports whether k matches [A-Za-z0-9_-]{1,MaxKeyLen}.
func validKey(k string) bool {
	if len(k) == 0 || len(k) > MaxKeyLen {
		return false
	}
	for i := 0; i < len(k); i++ {
		c := k[i]
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
	writeEmpty(w, http.StatusMethodNotAllowed)
}

func writeEmpty(w http.ResponseWriter, status int) {
	w.Header().Set("Content-Length", "0")
	w.WriteHeader(status)
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	h := w.Header()
	h.Set("Content-Type", contentType)
	h.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
