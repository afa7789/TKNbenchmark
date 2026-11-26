package kv

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
)

// MaxValueBytes is the largest value accepted by PUT /kv/<key>.
const MaxValueBytes = 1 << 20

const (
	maxKeyLen = 64
	kvPrefix  = "/kv/"
)

// Handler serves the key-value HTTP API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns a Handler serving store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// ServeHTTP routes requests. Routing is done on the raw (escaped) path so that
// encoded characters such as %2F are never mistaken for valid key bytes.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.EscapedPath()

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
		h.listKeys(w)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
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
		value, err := readBody(w, r)
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				writeStatus(w, http.StatusRequestEntityTooLarge)
			} else {
				writeStatus(w, http.StatusBadRequest)
			}
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

func (h *Handler) listKeys(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		slog.Error("encoding key list", "err", err)
		writeStatus(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func readBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	if r.ContentLength > MaxValueBytes {
		return nil, &http.MaxBytesError{Limit: MaxValueBytes}
	}
	body := http.MaxBytesReader(w, r.Body, MaxValueBytes)
	defer body.Close()
	if r.ContentLength >= 0 {
		buf := make([]byte, r.ContentLength)
		if _, err := io.ReadFull(body, buf); err != nil {
			return nil, err
		}
		return buf, nil
	}
	return io.ReadAll(body)
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

func writeStatus(w http.ResponseWriter, status int) {
	if status != http.StatusNoContent {
		w.Header().Set("Content-Length", "0")
	}
	w.WriteHeader(status)
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	hdr.Set("Content-Type", contentType)
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		slog.Debug("writing response body", "err", err)
	}
}
