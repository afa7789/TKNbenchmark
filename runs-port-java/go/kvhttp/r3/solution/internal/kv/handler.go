package kv

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
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

// Handler serves the key-value HTTP API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns a Handler backed by store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// ServeHTTP routes requests by raw path. A custom router is used instead of
// http.ServeMux so that paths are matched exactly, without cleaning or redirects.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			writeStatus(w, http.StatusMethodNotAllowed)
			return
		}
		writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			writeStatus(w, http.StatusMethodNotAllowed)
			return
		}
		h.listKeys(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			writeStatus(w, http.StatusBadRequest)
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
			writeStatus(w, http.StatusMethodNotAllowed)
		}
	default:
		writeStatus(w, http.StatusNotFound)
	}
}

func (h *Handler) get(w http.ResponseWriter, key string) {
	value, ok := h.store.Get(key)
	if !ok {
		writeStatus(w, http.StatusNotFound)
		return
	}
	writeBody(w, http.StatusOK, "application/octet-stream", value)
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

func (h *Handler) delete(w http.ResponseWriter, key string) {
	if h.store.Delete(key) {
		writeStatus(w, http.StatusNoContent)
	} else {
		writeStatus(w, http.StatusNotFound)
	}
}

func (h *Handler) listKeys(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		slog.Error("encode key list", "err", err)
		writeStatus(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > maxKeyLen {
		return false
	}
	for i := 0; i < len(key); i++ {
		c := key[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '_', c == '-':
		default:
			return false
		}
	}
	return true
}

func writeStatus(w http.ResponseWriter, status int) {
	if status != http.StatusNoContent {
		w.Header().Set("Content-Length", "0")
	}
	w.WriteHeader(status)
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	hdr.Set("Content-Type", contentType)
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		slog.Debug("write response", "err", err)
	}
}
