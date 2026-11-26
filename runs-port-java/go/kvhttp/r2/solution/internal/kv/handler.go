package kv

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
)

// MaxValueBytes is the largest value accepted by PUT.
const MaxValueBytes = 1 << 20

const (
	maxKeyLen = 64
	kvPrefix  = "/kv/"
)

// Handler routes requests for the key-value API.
type Handler struct {
	store *Store
}

// NewHandler returns an http.Handler serving the API backed by store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// ServeHTTP implements http.Handler. Routing is done by hand on the raw
// request path so that no path cleaning or unescaping alters the key.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		writeBody(w, http.StatusOK, []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		h.listKeys(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			h.getValue(w, key)
		case http.MethodPut:
			h.putValue(w, r, key)
		case http.MethodDelete:
			h.deleteValue(w, key)
		default:
			methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
		}
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func (h *Handler) listKeys(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	writeBody(w, http.StatusOK, body)
}

func (h *Handler) getValue(w http.ResponseWriter, key string) {
	value, ok := h.store.Get(key)
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	writeBody(w, http.StatusOK, value)
}

func (h *Handler) putValue(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > MaxValueBytes {
		w.WriteHeader(http.StatusRequestEntityTooLarge)
		return
	}
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			w.WriteHeader(http.StatusRequestEntityTooLarge)
		} else {
			w.WriteHeader(http.StatusBadRequest)
		}
		return
	}
	status := http.StatusOK
	if h.store.Put(key, value) {
		status = http.StatusCreated
	}
	w.Header().Set("Content-Length", "0")
	w.WriteHeader(status)
}

func (h *Handler) deleteValue(w http.ResponseWriter, key string) {
	if !h.store.Delete(key) {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func writeBody(w http.ResponseWriter, status int, body []byte) {
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	w.WriteHeader(http.StatusMethodNotAllowed)
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
