package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"kvhttp/internal/kv"
)

const (
	kvPrefix     = "/kv/"
	maxKeyLength = 64
	maxBodyBytes = 1 << 20 // 1 MiB
)

// handler routes requests to the key/value store. It deliberately does not
// use http.ServeMux so that paths are matched exactly as sent, without
// cleaning or redirects.
type handler struct {
	store *kv.Store
}

func newHandler(store *kv.Store) *handler {
	return &handler{store: store}
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, "GET")
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		io.WriteString(w, "ok")
	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, "GET")
			return
		}
		h.listKeys(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		h.handleKey(w, r, key)
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func (h *handler) handleKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Content-Length", strconv.Itoa(len(value)))
		w.Write(value)
	case http.MethodPut:
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
		if err != nil {
			if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
				w.WriteHeader(http.StatusRequestEntityTooLarge)
			} else {
				w.WriteHeader(http.StatusBadRequest)
			}
			return
		}
		if h.store.Put(key, body) {
			w.WriteHeader(http.StatusCreated)
		} else {
			w.WriteHeader(http.StatusOK)
		}
	case http.MethodDelete:
		if h.store.Delete(key) {
			w.WriteHeader(http.StatusNoContent)
		} else {
			w.WriteHeader(http.StatusNotFound)
		}
	default:
		methodNotAllowed(w, "GET, PUT, DELETE")
	}
}

func (h *handler) listKeys(w http.ResponseWriter) {
	keys := h.store.Keys()
	if keys == nil {
		keys = []string{} // encode as [] rather than null
	}
	body, err := json.Marshal(keys)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.Write(body)
}

func methodNotAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	w.WriteHeader(http.StatusMethodNotAllowed)
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > maxKeyLength {
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
