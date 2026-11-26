package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strings"
)

const (
	maxKeyLength = 64
	maxValueSize = 1 << 20 // 1 MiB
	kvPrefix     = "/kv/"
)

// Handler routes requests to the key-value API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns an http.Handler serving the API for store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Use the escaped path so percent-encoded characters are never mistaken
	// for valid key characters.
	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		h.health(w, r)
	case path == "/kv":
		h.list(w, r)
	case strings.HasPrefix(path, kvPrefix):
		h.key(w, r, strings.TrimPrefix(path, kvPrefix))
	default:
		writeText(w, http.StatusNotFound, "not found")
	}
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, "GET")
		return
	}
	writeText(w, http.StatusOK, "ok")
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, "GET")
		return
	}
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		log.Printf("encode keys: %v", err)
		writeText(w, http.StatusInternalServerError, "internal server error")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(body)
}

func (h *Handler) key(w http.ResponseWriter, r *http.Request, key string) {
	if !validKey(key) {
		writeText(w, http.StatusBadRequest, "invalid key")
		return
	}
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			writeText(w, http.StatusNotFound, "not found")
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		w.WriteHeader(http.StatusOK)
		w.Write(value)
	case http.MethodPut:
		value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxValueSize))
		if err != nil {
			if maxErr := (*http.MaxBytesError)(nil); errors.As(err, &maxErr) {
				writeText(w, http.StatusRequestEntityTooLarge, "value too large")
			} else {
				writeText(w, http.StatusBadRequest, "bad request body")
			}
			return
		}
		if h.store.Put(key, value) {
			w.WriteHeader(http.StatusCreated)
		} else {
			w.WriteHeader(http.StatusOK)
		}
	case http.MethodDelete:
		if !h.store.Delete(key) {
			writeText(w, http.StatusNotFound, "not found")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		methodNotAllowed(w, "GET, PUT, DELETE")
	}
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

func methodNotAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	writeText(w, http.StatusMethodNotAllowed, "method not allowed")
}

func writeText(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(status)
	io.WriteString(w, body)
}
