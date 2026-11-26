// Package server maps HTTP requests onto the key/value API.
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

const (
	// MaxValueBytes is the largest accepted value (request body) size.
	MaxValueBytes = 1 << 20
	// maxDrainBytes bounds how much of a rejected body is discarded before
	// replying, so the client sees the response instead of a reset.
	maxDrainBytes = 64 << 20

	maxKeyLength = 64
	kvPrefix     = "/kv/"
)

// Handler serves the key/value API backed by a Store.
type Handler struct {
	store *store.Store
}

// New returns a Handler backed by s.
func New(s *store.Store) *Handler {
	return &Handler{store: s}
}

// ValidKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func ValidKey(key string) bool {
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

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Route on the raw request target so percent-encoded or otherwise
	// non-canonical paths are judged exactly as sent.
	path := r.RequestURI

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
		body, err := json.Marshal(h.store.Keys())
		if err != nil {
			log.Printf("kvhttp: encoding key list: %v", err)
			writeStatus(w, http.StatusInternalServerError)
			return
		}
		writeBody(w, http.StatusOK, "application/json", body)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !ValidKey(key) {
			writeStatus(w, http.StatusBadRequest)
			return
		}
		h.serveKey(w, r, key)
	default:
		writeStatus(w, http.StatusNotFound)
	}
}

func (h *Handler) serveKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			writeStatus(w, http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", value)
	case http.MethodPut:
		value, err := readValue(r)
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				drain(r.Body)
				writeStatus(w, http.StatusRequestEntityTooLarge)
				return
			}
			writeStatus(w, http.StatusBadRequest)
			return
		}
		if h.store.Put(key, value) {
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

// readValue reads the request body, enforcing MaxValueBytes.
func readValue(r *http.Request) ([]byte, error) {
	if r.ContentLength > MaxValueBytes {
		return nil, &http.MaxBytesError{Limit: MaxValueBytes}
	}
	body := http.MaxBytesReader(nil, r.Body, MaxValueBytes)
	if r.ContentLength > 0 {
		buf := make([]byte, r.ContentLength)
		if _, err := io.ReadFull(body, buf); err != nil {
			return nil, err
		}
		return buf, nil
	}
	return io.ReadAll(body)
}

// drain discards up to maxDrainBytes of unread body.
func drain(body io.Reader) {
	_, _ = io.CopyN(io.Discard, body, maxDrainBytes)
}

func writeStatus(w http.ResponseWriter, status int) {
	if status == http.StatusNoContent {
		w.WriteHeader(status)
		return
	}
	writeBody(w, status, "", nil)
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	if contentType != "" {
		hdr.Set("Content-Type", contentType)
	}
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if len(body) > 0 {
		if _, err := w.Write(body); err != nil {
			log.Printf("kvhttp: writing response: %v", err)
		}
	}
}
