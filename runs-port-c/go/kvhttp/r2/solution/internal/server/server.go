// Package server implements the kvhttp HTTP API on top of a store.Store.
package server

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"kvhttp/internal/store"
)

const (
	// MaxValueSize is the largest value, in bytes, a client may store.
	MaxValueSize = 1 << 20
	// MaxKeyLen is the longest permitted key.
	MaxKeyLen = 64

	// maxDrain bounds how much of an oversized body is read and discarded
	// before replying, so the client sees the 413 instead of a reset.
	maxDrain = 4 * MaxValueSize

	kvPrefix = "/kv/"
)

// Handler serves the key-value API.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

// ServeHTTP routes on the raw request target so that percent-encoded
// characters are never decoded into something that looks like a valid key.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.RequestURI
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			status(w, http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		writeBody(w, []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			status(w, http.StatusMethodNotAllowed)
			return
		}
		h.list(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !ValidKey(key) {
			status(w, http.StatusBadRequest)
			return
		}
		h.key(w, r, key)
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
	writeBody(w, body)
}

func (h *Handler) key(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		v, ok := h.store.Get(key)
		if !ok {
			status(w, http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		writeBody(w, v)
	case http.MethodPut:
		value, err := readValue(r)
		if err != nil {
			if errors.Is(err, errTooLarge) {
				status(w, http.StatusRequestEntityTooLarge)
			} else {
				status(w, http.StatusBadRequest)
			}
			return
		}
		if h.store.Put(key, value) {
			status(w, http.StatusCreated)
		} else {
			status(w, http.StatusOK)
		}
	case http.MethodDelete:
		if h.store.Delete(key) {
			status(w, http.StatusNoContent)
		} else {
			status(w, http.StatusNotFound)
		}
	default:
		status(w, http.StatusMethodNotAllowed)
	}
}

var errTooLarge = errors.New("value too large")

// readValue reads the request body, rejecting anything over MaxValueSize.
// Oversized bodies are partially drained so the error response is delivered
// cleanly rather than lost to a connection reset.
func readValue(r *http.Request) ([]byte, error) {
	if r.ContentLength > MaxValueSize {
		drain(r.Body)
		return nil, errTooLarge
	}
	var buf bytes.Buffer
	if r.ContentLength > 0 {
		// Room for the whole body plus the final read that observes EOF.
		buf.Grow(int(r.ContentLength) + bytes.MinRead)
	}
	if _, err := buf.ReadFrom(io.LimitReader(r.Body, MaxValueSize+1)); err != nil {
		return nil, err
	}
	b := buf.Bytes()
	if len(b) > MaxValueSize {
		drain(r.Body)
		return nil, errTooLarge
	}
	return b, nil
}

func drain(r io.Reader) {
	_, _ = io.CopyN(io.Discard, r, maxDrain)
}

// ValidKey reports whether k matches [A-Za-z0-9_-]{1,64}.
func ValidKey(k string) bool {
	if len(k) == 0 || len(k) > MaxKeyLen {
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

func status(w http.ResponseWriter, code int) {
	if code != http.StatusNoContent {
		w.Header().Set("Content-Length", "0")
	}
	w.WriteHeader(code)
}

func writeBody(w http.ResponseWriter, body []byte) {
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}
