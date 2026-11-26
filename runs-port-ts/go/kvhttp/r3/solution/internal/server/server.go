// Package server implements the kvhttp HTTP API on top of a store.Store.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"kvhttp/internal/store"
)

// MaxValueBytes is the largest value accepted by PUT /kv/<key>.
const MaxValueBytes = 1 << 20

const (
	maxKeyLen = 64
	kvPrefix  = "/kv/"
)

// Handler serves the kvhttp routes.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

// ServeHTTP routes on the raw request path so that percent-encoded or
// non-canonical paths are judged exactly as sent.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.RequestURI

	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		send(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))

	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		body, err := json.Marshal(h.store.Keys())
		if err != nil {
			internalError(w, err)
			return
		}
		send(w, http.StatusOK, "application/json", body)

	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			sendError(w, http.StatusBadRequest, "invalid key")
			return
		}
		h.serveKey(w, r, key)

	default:
		sendStatus(w, http.StatusNotFound)
	}
}

func (h *Handler) serveKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			sendStatus(w, http.StatusNotFound)
			return
		}
		send(w, http.StatusOK, "application/octet-stream", value)

	case http.MethodPut:
		if r.ContentLength > MaxValueBytes {
			tooLarge(w)
			return
		}
		value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueBytes))
		if err != nil {
			if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
				tooLarge(w)
				return
			}
			// The client went away or sent a malformed body.
			sendError(w, http.StatusBadRequest, "bad request body")
			return
		}
		status := http.StatusOK
		if h.store.Set(key, value) {
			status = http.StatusCreated
		}
		sendStatusEmpty(w, status)

	case http.MethodDelete:
		if !h.store.Delete(key) {
			sendStatus(w, http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)

	default:
		methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
	}
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

func send(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	if len(body) > 0 {
		hdr.Set("Content-Type", contentType)
	}
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		log.Printf("write response: %v", err)
	}
}

func sendError(w http.ResponseWriter, status int, msg string) {
	send(w, status, "text/plain; charset=utf-8", []byte(msg))
}

func sendStatus(w http.ResponseWriter, status int) {
	sendError(w, status, http.StatusText(status))
}

func sendStatusEmpty(w http.ResponseWriter, status int) {
	send(w, status, "", nil)
}

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	sendStatus(w, http.StatusMethodNotAllowed)
}

func tooLarge(w http.ResponseWriter) {
	// The unread body makes the connection unusable; tell the client it is closing.
	w.Header().Set("Connection", "close")
	sendStatus(w, http.StatusRequestEntityTooLarge)
}

func internalError(w http.ResponseWriter, err error) {
	log.Printf("internal error: %v", err)
	sendError(w, http.StatusInternalServerError, "internal error")
}
