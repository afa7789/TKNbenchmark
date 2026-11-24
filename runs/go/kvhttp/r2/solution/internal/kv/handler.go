package kv

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
)

const (
	// MaxValueSize is the largest value, in bytes, that may be stored.
	MaxValueSize = 1 << 20
	// MaxKeyLen is the longest permitted key.
	MaxKeyLen = 64

	kvPrefix = "/kv/"
)

// Handler serves the key-value HTTP API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns an http.Handler exposing store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// ServeHTTP routes requests. Routing is done by hand rather than with
// http.ServeMux because the mux cleans paths and issues redirects, whereas
// this API must judge the raw path exactly as sent.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.EscapedPath()
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
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			writeError(w, http.StatusBadRequest)
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
		writeError(w, http.StatusNotFound)
	}
}

func (h *Handler) list(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		writeError(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) get(w http.ResponseWriter, key string) {
	v, ok := h.store.Get(key)
	if !ok {
		writeError(w, http.StatusNotFound)
		return
	}
	writeBody(w, http.StatusOK, "application/octet-stream", v)
}

func (h *Handler) put(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > MaxValueSize {
		writeError(w, http.StatusRequestEntityTooLarge)
		return
	}
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueSize))
	if err != nil {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			writeError(w, http.StatusRequestEntityTooLarge)
			return
		}
		writeError(w, http.StatusBadRequest)
		return
	}
	status := http.StatusOK
	if h.store.Put(key, value) {
		status = http.StatusCreated
	}
	writeBody(w, status, "", nil)
}

func (h *Handler) delete(w http.ResponseWriter, key string) {
	if !h.store.Delete(key) {
		writeError(w, http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > MaxKeyLen {
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

// allow writes a 405 response and returns false unless r uses method.
func allow(w http.ResponseWriter, r *http.Request, method string) bool {
	if r.Method == method {
		return true
	}
	methodNotAllowed(w, method)
	return false
}

func methodNotAllowed(w http.ResponseWriter, methods ...string) {
	w.Header().Set("Allow", strings.Join(methods, ", "))
	writeError(w, http.StatusMethodNotAllowed)
}

func writeError(w http.ResponseWriter, status int) {
	writeBody(w, status, "text/plain; charset=utf-8", []byte(http.StatusText(status)+"\n"))
}

// writeBody writes a complete response with an explicit Content-Length so
// that large bodies are never sent chunked.
func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	if contentType != "" {
		hdr.Set("Content-Type", contentType)
	}
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
