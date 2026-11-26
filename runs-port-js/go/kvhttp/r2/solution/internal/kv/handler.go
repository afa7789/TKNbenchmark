package kv

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
)

// MaxValueBytes is the largest value accepted by PUT.
const MaxValueBytes = 1 << 20

const maxKeyLen = 64

// Handler serves the key-value HTTP API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns an http.Handler exposing store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Route on the raw request path so that escaped characters are rejected
	// as invalid keys instead of being silently decoded.
	path := r.URL.EscapedPath()
	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			sendError(w, http.StatusMethodNotAllowed)
			return
		}
		send(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			sendError(w, http.StatusMethodNotAllowed)
			return
		}
		h.list(w)
	case strings.HasPrefix(path, "/kv/"):
		h.serveKey(w, r, strings.TrimPrefix(path, "/kv/"))
	default:
		sendError(w, http.StatusNotFound)
	}
}

func (h *Handler) list(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		log.Printf("encode keys: %v", err)
		sendError(w, http.StatusInternalServerError)
		return
	}
	send(w, http.StatusOK, "application/json", body)
}

func (h *Handler) serveKey(w http.ResponseWriter, r *http.Request, key string) {
	if !validKey(key) {
		sendError(w, http.StatusBadRequest)
		return
	}
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			sendError(w, http.StatusNotFound)
			return
		}
		send(w, http.StatusOK, "application/octet-stream", value)
	case http.MethodPut:
		value, status := readValue(w, r)
		if status != 0 {
			sendError(w, status)
			return
		}
		if h.store.Put(key, value) {
			send(w, http.StatusOK, "", nil)
		} else {
			send(w, http.StatusCreated, "", nil)
		}
	case http.MethodDelete:
		if !h.store.Delete(key) {
			sendError(w, http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		sendError(w, http.StatusMethodNotAllowed)
	}
}

// readValue reads the request body, enforcing MaxValueBytes. On failure it
// returns a non-zero HTTP status describing the problem.
func readValue(w http.ResponseWriter, r *http.Request) ([]byte, int) {
	if r.ContentLength > MaxValueBytes {
		return nil, http.StatusRequestEntityTooLarge
	}
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxValueBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			return nil, http.StatusRequestEntityTooLarge
		}
		return nil, http.StatusBadRequest
	}
	return value, 0
}

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
	if contentType != "" {
		hdr.Set("Content-Type", contentType)
	}
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if len(body) > 0 {
		_, _ = w.Write(body)
	}
}

// sendError writes an empty-bodied error response and asks the client to close
// the connection, since any unread request body is not worth draining.
func sendError(w http.ResponseWriter, status int) {
	w.Header().Set("Connection", "close")
	send(w, status, "", nil)
}
