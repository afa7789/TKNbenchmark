// Package server implements the kvhttp HTTP API on top of a store.Store.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"kvhttp/internal/store"
)

// MaxValueBytes is the largest value accepted by PUT /kv/<key>.
const MaxValueBytes = 1 << 20

const kvPrefix = "/kv/"

var keyPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// Handler serves the kvhttp routes.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

// ServeHTTP routes on the raw (undecoded, uncleaned) request path so that
// percent-encoded or dot-segment keys are rejected rather than reinterpreted.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path, _, _ := strings.Cut(r.URL.EscapedPath(), "?")

	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		send(w, http.StatusOK, []byte("ok"), "text/plain; charset=utf-8")

	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		body, err := json.Marshal(h.store.Keys())
		if err != nil {
			log.Printf("encode keys: %v", err)
			send(w, http.StatusInternalServerError, nil, "")
			return
		}
		send(w, http.StatusOK, body, "application/json")

	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !keyPattern.MatchString(key) {
			send(w, http.StatusBadRequest, nil, "")
			return
		}
		h.serveKey(w, r, key)

	default:
		send(w, http.StatusNotFound, nil, "")
	}
}

func (h *Handler) serveKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			send(w, http.StatusNotFound, nil, "")
			return
		}
		send(w, http.StatusOK, value, "application/octet-stream")

	case http.MethodPut:
		value, err := readBody(w, r)
		if err != nil {
			var tooLarge *http.MaxBytesError
			status := http.StatusBadRequest
			if errors.As(err, &tooLarge) {
				status = http.StatusRequestEntityTooLarge
			}
			w.Header().Set("Connection", "close")
			send(w, status, nil, "")
			return
		}
		status := http.StatusOK
		if h.store.Set(key, value) {
			status = http.StatusCreated
		}
		send(w, status, nil, "")

	case http.MethodDelete:
		status := http.StatusNotFound
		if h.store.Delete(key) {
			status = http.StatusNoContent
		}
		send(w, status, nil, "")

	default:
		methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
	}
}

func readBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	if r.ContentLength > MaxValueBytes {
		return nil, &http.MaxBytesError{Limit: MaxValueBytes}
	}
	return io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueBytes))
}

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	send(w, http.StatusMethodNotAllowed, nil, "")
}

func send(w http.ResponseWriter, status int, body []byte, contentType string) {
	hdr := w.Header()
	if contentType != "" {
		hdr.Set("Content-Type", contentType)
	}
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if len(body) > 0 {
		if _, err := w.Write(body); err != nil {
			log.Printf("write response: %v", err)
		}
	}
}
