// Package server implements the kvhttp HTTP key-value API.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
)

// MaxValueBytes is the largest value the server accepts.
const MaxValueBytes = 1 << 20

const keyPrefix = "/kv/"

// Handler serves the kvhttp API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns a Handler backed by store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Connection", "close")

	// Route on the raw request target so percent-encoded bytes are not
	// silently decoded into valid key characters.
	path, _, _ := strings.Cut(r.RequestURI, "?")

	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, "GET")
			return
		}
		writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, "GET")
			return
		}
		h.listKeys(w)
	case strings.HasPrefix(path, keyPrefix):
		key := strings.TrimPrefix(path, keyPrefix)
		if !validKey(key) {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		h.serveKey(w, r, key)
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func (h *Handler) listKeys(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		slog.Error("encoding key list", "err", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) serveKey(w http.ResponseWriter, r *http.Request, key string) {
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", value)
	case http.MethodPut:
		value, err := readValue(w, r)
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				w.WriteHeader(http.StatusRequestEntityTooLarge)
				return
			}
			// The client went away or sent a malformed body.
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if h.store.Put(key, value) {
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

func readValue(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	if r.ContentLength > MaxValueBytes {
		return nil, &http.MaxBytesError{Limit: MaxValueBytes}
	}
	body := http.MaxBytesReader(w, r.Body, MaxValueBytes)
	if r.ContentLength >= 0 {
		buf := make([]byte, r.ContentLength)
		if _, err := io.ReadFull(body, buf); err != nil {
			return nil, err
		}
		return buf, nil
	}
	return io.ReadAll(body)
}

func validKey(key string) bool {
	if len(key) == 0 || len(key) > 64 {
		return false
	}
	for i := 0; i < len(key); i++ {
		switch c := key[i]; {
		case 'a' <= c && c <= 'z', 'A' <= c && c <= 'Z', '0' <= c && c <= '9', c == '_', c == '-':
		default:
			return false
		}
	}
	return true
}

func methodNotAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		slog.Debug("writing response", "err", err)
	}
}
