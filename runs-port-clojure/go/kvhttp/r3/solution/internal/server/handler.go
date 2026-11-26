// Package server implements the kvhttp HTTP API.
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

// MaxBodyBytes caps request bodies. Values are limited to 1 MiB by the
// spec; the extra headroom means oversized bodies are never cut mid-read.
const MaxBodyBytes = 8 << 20

const kvPrefix = "/kv/"

// Handler serves the kvhttp routes backed by a Store.
type Handler struct {
	store *store.Store
}

// New returns a Handler serving data from s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

// ServeHTTP dispatches on the raw request path. http.ServeMux is avoided
// on purpose: it cleans and redirects paths, which would hide invalid keys.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := rawPath(r)
	switch {
	case path == "/health":
		h.health(w, r)
	case path == "/kv":
		h.listKeys(w, r)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			writeStatus(w, http.StatusBadRequest)
			return
		}
		h.entry(w, r, key)
	default:
		writeStatus(w, http.StatusNotFound)
	}
}

// rawPath returns the undecoded request path without any query string.
func rawPath(r *http.Request) string {
	p := r.RequestURI
	if i := strings.IndexByte(p, '?'); i >= 0 {
		p = p[:i]
	}
	if p == "" || p[0] != '/' {
		// Absolute-form request target; fall back to the parsed URL.
		p = r.URL.EscapedPath()
	}
	return p
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

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeStatus(w, http.StatusMethodNotAllowed)
		return
	}
	writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
}

func (h *Handler) listKeys(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeStatus(w, http.StatusMethodNotAllowed)
		return
	}
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) entry(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		v, ok := h.store.Get(key)
		if !ok {
			writeStatus(w, http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", v)
	case http.MethodPut:
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxBodyBytes))
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				writeStatus(w, http.StatusRequestEntityTooLarge)
			} else {
				writeStatus(w, http.StatusBadRequest)
			}
			return
		}
		if h.store.Put(key, body) {
			writeStatus(w, http.StatusCreated)
		} else {
			writeStatus(w, http.StatusOK)
		}
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

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	hdr.Set("Content-Type", contentType)
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

// writeStatus sends an empty-bodied response with an explicit zero length.
func writeStatus(w http.ResponseWriter, status int) {
	if status != http.StatusNoContent {
		w.Header().Set("Content-Length", "0")
	}
	w.WriteHeader(status)
}
