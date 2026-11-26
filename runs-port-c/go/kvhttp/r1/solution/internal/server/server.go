// Package server implements the kvhttp HTTP API on top of a store.Store.
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
	// MaxValueBytes is the maximum size of a stored value.
	MaxValueBytes = 1 << 20
)

// Handler serves the kvhttp routes.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Route on the raw request target so percent-escapes are not decoded
	// into otherwise valid keys.
	path := r.RequestURI
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			notAllowed(w, "GET")
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		writeBody(w, http.StatusOK, []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			notAllowed(w, "GET")
			return
		}
		h.list(w)
	case strings.HasPrefix(path, "/kv/"):
		key := path[len("/kv/"):]
		if !ValidKey(key) {
			status(w, http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			h.get(w, key)
		case http.MethodPut:
			h.put(w, r, key)
		case http.MethodDelete:
			if h.store.Delete(key) {
				status(w, http.StatusNoContent)
			} else {
				status(w, http.StatusNotFound)
			}
		default:
			notAllowed(w, "GET, PUT, DELETE")
		}
	default:
		status(w, http.StatusNotFound)
	}
}

func (h *Handler) list(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		status(w, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	writeBody(w, http.StatusOK, body)
}

func (h *Handler) get(w http.ResponseWriter, key string) {
	v, ok := h.store.Get(key)
	if !ok {
		status(w, http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	writeBody(w, http.StatusOK, v)
}

func (h *Handler) put(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > MaxValueBytes {
		status(w, http.StatusRequestEntityTooLarge)
		return
	}
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueBytes))
	if err != nil {
		if _, tooLarge := errors.AsType[*http.MaxBytesError](err); tooLarge {
			status(w, http.StatusRequestEntityTooLarge)
		}
		// Otherwise the client went away or timed out; nothing to reply to.
		return
	}
	if h.store.Put(key, value) {
		status(w, http.StatusCreated)
	} else {
		status(w, http.StatusOK)
	}
}

// ValidKey reports whether k matches [A-Za-z0-9_-]{1,64}.
func ValidKey(k string) bool {
	if len(k) == 0 || len(k) > MaxKeyLen {
		return false
	}
	for i := 0; i < len(k); i++ {
		c := k[i]
		switch {
		case c >= 'A' && c <= 'Z', c >= 'a' && c <= 'z', c >= '0' && c <= '9', c == '_', c == '-':
		default:
			return false
		}
	}
	return true
}

func writeBody(w http.ResponseWriter, code int, body []byte) {
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(code)
	_, _ = w.Write(body)
}

func status(w http.ResponseWriter, code int) {
	if code != http.StatusNoContent {
		w.Header().Set("Content-Length", "0")
	}
	w.WriteHeader(code)
}

func notAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	status(w, http.StatusMethodNotAllowed)
}
