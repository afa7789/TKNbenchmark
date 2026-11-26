// Package server implements the kvhttp HTTP routes.
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

// MaxValueBytes is the largest value accepted by PUT /kv/<key>.
const MaxValueBytes = 1 << 20

const (
	maxKeyLen = 64
	kvPrefix  = "/kv/"
)

// Handler serves the kvhttp API backed by a Store.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

// ServeHTTP dispatches on the raw (still percent-encoded) request path so
// that encoded characters are never mistaken for valid key characters.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		h.health(w, r)
	case path == "/kv":
		h.list(w, r)
	case strings.HasPrefix(path, kvPrefix):
		h.item(w, r, path[len(kvPrefix):])
	default:
		writeStatus(w, http.StatusNotFound)
	}
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeStatus(w, http.StatusMethodNotAllowed)
		return
	}
	writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeStatus(w, http.StatusMethodNotAllowed)
		return
	}
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		writeStatus(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) item(w http.ResponseWriter, r *http.Request, key string) {
	if !validKey(key) {
		writeStatus(w, http.StatusBadRequest)
		return
	}
	switch r.Method {
	case http.MethodGet:
		v, ok := h.store.Get(key)
		if !ok {
			writeStatus(w, http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", v)
	case http.MethodPut:
		h.put(w, r, key)
	case http.MethodDelete:
		if h.store.Delete(key) {
			writeStatus(w, http.StatusNoContent)
		} else {
			writeStatus(w, http.StatusNotFound)
		}
	default:
		writeStatus(w, http.StatusMethodNotAllowed)
	}
}

func (h *Handler) put(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > MaxValueBytes {
		writeStatus(w, http.StatusRequestEntityTooLarge)
		return
	}
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeStatus(w, http.StatusRequestEntityTooLarge)
		} else {
			writeStatus(w, http.StatusBadRequest)
		}
		return
	}
	if h.store.Put(key, value) {
		writeStatus(w, http.StatusCreated)
	} else {
		writeStatus(w, http.StatusOK)
	}
}

// validKey reports whether k matches [A-Za-z0-9_-]{1,64}.
func validKey(k string) bool {
	if len(k) == 0 || len(k) > maxKeyLen {
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

// writeBody writes a complete response with an explicit Content-Length.
func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	hdr.Set("Content-Type", contentType)
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

// writeStatus writes a response with an empty body.
func writeStatus(w http.ResponseWriter, status int) {
	if status != http.StatusNoContent {
		w.Header().Set("Content-Length", "0")
	}
	w.WriteHeader(status)
}
