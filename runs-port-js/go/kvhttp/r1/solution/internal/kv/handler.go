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

// MaxValueBytes is the largest value the server accepts.
const MaxValueBytes = 1 << 20

const kvPrefix = "/kv/"

// Handler serves the key-value HTTP API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns a Handler backed by store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Always drain the body first so error responses don't reset the connection.
	body, err := readBody(w, r)
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			w.Header().Set("Connection", "close")
			writeError(w, http.StatusRequestEntityTooLarge)
			return
		}
		writeError(w, http.StatusBadRequest)
		return
	}

	// Route on the raw request target so percent-encoded or dot-segment
	// paths are judged exactly as sent.
	path := r.RequestURI
	switch {
	case path == "/health":
		h.health(w, r)
	case path == "/kv":
		h.list(w, r)
	case strings.HasPrefix(path, kvPrefix):
		key := path[len(kvPrefix):]
		if !validKey(key) {
			writeError(w, http.StatusBadRequest)
			return
		}
		h.item(w, r, key, body)
	default:
		writeError(w, http.StatusNotFound)
	}
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	write(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	data, err := json.Marshal(h.store.Keys())
	if err != nil {
		log.Printf("encode keys: %v", err)
		writeError(w, http.StatusInternalServerError)
		return
	}
	write(w, http.StatusOK, "application/json", data)
}

func (h *Handler) item(w http.ResponseWriter, r *http.Request, key string, body []byte) {
	switch r.Method {
	case http.MethodGet:
		value, ok := h.store.Get(key)
		if !ok {
			writeError(w, http.StatusNotFound)
			return
		}
		write(w, http.StatusOK, "application/octet-stream", value)
	case http.MethodPut:
		status := http.StatusOK
		if h.store.Put(key, body) {
			status = http.StatusCreated
		}
		write(w, status, "", nil)
	case http.MethodDelete:
		if !h.store.Delete(key) {
			writeError(w, http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
	}
}

// readBody reads the whole request body, failing with *http.MaxBytesError
// if it exceeds MaxValueBytes.
func readBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	if r.ContentLength > MaxValueBytes {
		return nil, &http.MaxBytesError{Limit: MaxValueBytes}
	}
	body := http.MaxBytesReader(w, r.Body, MaxValueBytes)
	defer body.Close()
	data, err := io.ReadAll(body)
	if err != nil {
		return nil, err
	}
	if data == nil {
		data = []byte{}
	}
	return data, nil
}

// validKey reports whether key matches [A-Za-z0-9_-]{1,64}.
func validKey(key string) bool {
	if len(key) == 0 || len(key) > 64 {
		return false
	}
	for i := 0; i < len(key); i++ {
		c := key[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '_', c == '-':
		default:
			return false
		}
	}
	return true
}

func write(w http.ResponseWriter, status int, contentType string, body []byte) {
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

func writeError(w http.ResponseWriter, status int) {
	w.Header().Set("X-Content-Type-Options", "nosniff")
	write(w, status, "text/plain; charset=utf-8", []byte(http.StatusText(status)))
}

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	writeError(w, http.StatusMethodNotAllowed)
}
