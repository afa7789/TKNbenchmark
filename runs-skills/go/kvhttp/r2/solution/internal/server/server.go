// Package server implements the kvhttp HTTP API on top of a store.Store.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"kvhttp/internal/store"
)

// MaxValueSize is the largest value, in bytes, accepted by PUT /kv/<key>.
const MaxValueSize = 1 << 20

const maxKeyLen = 64

// Handler serves the kvhttp routes. It routes on the raw request path itself
// rather than using http.ServeMux, so that unclean paths (e.g. "/kv/a/../b")
// are rejected as invalid keys instead of being redirected.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	switch {
	case path == "/health":
		if !allow(w, r, http.MethodGet) {
			return
		}
		writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
	case path == "/kv":
		if !allow(w, r, http.MethodGet) {
			return
		}
		h.list(w)
	case strings.HasPrefix(path, "/kv/"):
		h.item(w, r, strings.TrimPrefix(path, "/kv/"))
	default:
		http.NotFound(w, r)
	}
}

func (h *Handler) list(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		slog.Error("encode key list", "err", err)
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) item(w http.ResponseWriter, r *http.Request, key string) {
	if !allow(w, r, http.MethodGet, http.MethodPut, http.MethodDelete) {
		return
	}
	if !validKey(key) {
		http.Error(w, "invalid key", http.StatusBadRequest)
		return
	}

	switch r.Method {
	case http.MethodGet:
		v, ok := h.store.Get(key)
		if !ok {
			http.NotFound(w, r)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", v)
	case http.MethodPut:
		value, err := readValue(w, r)
		if err != nil {
			if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
				http.Error(w, "value too large", http.StatusRequestEntityTooLarge)
				return
			}
			http.Error(w, "read body", http.StatusBadRequest)
			return
		}
		status := http.StatusOK
		if h.store.Put(key, value) {
			status = http.StatusCreated
		}
		w.Header().Set("Content-Length", "0")
		w.WriteHeader(status)
	case http.MethodDelete:
		if !h.store.Delete(key) {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// readValue reads the full request body, enforcing MaxValueSize.
func readValue(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	body := http.MaxBytesReader(w, r.Body, MaxValueSize)
	if r.ContentLength > MaxValueSize {
		return nil, &http.MaxBytesError{Limit: MaxValueSize}
	}
	if r.ContentLength >= 0 {
		buf := make([]byte, r.ContentLength)
		if _, err := io.ReadFull(body, buf); err != nil {
			return nil, err
		}
		return buf, nil
	}
	return io.ReadAll(body)
}

// allow reports whether r.Method is one of methods. If not, it writes a 405
// response with an Allow header and returns false.
func allow(w http.ResponseWriter, r *http.Request, methods ...string) bool {
	for _, m := range methods {
		if r.Method == m {
			return true
		}
	}
	w.Header().Set("Allow", strings.Join(methods, ", "))
	http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
	return false
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		slog.Debug("write response", "err", err)
	}
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
