package kv

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
)

// MaxValueSize is the largest value, in bytes, that may be stored.
const MaxValueSize = 1 << 20

const maxKeyLen = 64

// Handler serves the key-value HTTP API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns an http.Handler exposing store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// ServeHTTP routes requests. Routing is done by hand rather than with
// http.ServeMux so that malformed keys yield 400 instead of 404 or a redirect.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		writeBody(w, "text/plain; charset=utf-8", []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		h.list(w)
	case strings.HasPrefix(path, "/kv/"):
		key := strings.TrimPrefix(path, "/kv/")
		if !validKey(key) {
			http.Error(w, "invalid key", http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			h.get(w, key)
		case http.MethodPut:
			h.put(w, r, key)
		case http.MethodDelete:
			h.delete(w, key)
		default:
			methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
		}
	default:
		http.NotFound(w, r)
	}
}

func (h *Handler) list(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	writeBody(w, "application/json", body)
}

func (h *Handler) get(w http.ResponseWriter, key string) {
	v, ok := h.store.Get(key)
	if !ok {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	writeBody(w, "application/octet-stream", v)
}

func (h *Handler) put(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > MaxValueSize {
		http.Error(w, "value too large", http.StatusRequestEntityTooLarge)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueSize))
	if err != nil {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			http.Error(w, "value too large", http.StatusRequestEntityTooLarge)
			return
		}
		http.Error(w, "cannot read body", http.StatusBadRequest)
		return
	}
	status := http.StatusOK
	if h.store.Put(key, body) {
		status = http.StatusCreated
	}
	w.Header().Set("Content-Length", "0")
	w.WriteHeader(status)
}

func (h *Handler) delete(w http.ResponseWriter, key string) {
	if !h.store.Delete(key) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func writeBody(w http.ResponseWriter, contentType string, body []byte) {
	hdr := w.Header()
	hdr.Set("Content-Type", contentType)
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > maxKeyLen {
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
