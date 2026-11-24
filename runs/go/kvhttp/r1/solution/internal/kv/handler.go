package kv

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
)

// MaxValueSize is the largest value accepted by PUT.
const MaxValueSize = 1 << 20

const maxKeyLen = 64

// Handler serves the key-value HTTP API backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns an http.Handler exposing store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// ServeHTTP routes on the raw request path so that keys are validated exactly
// as sent, without the cleaning or unescaping performed by http.ServeMux.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := rawPath(r)

	switch {
	case path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))

	case path == "/kv":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		h.list(w)

	case strings.HasPrefix(path, "/kv/"):
		key := path[len("/kv/"):]
		if !validKey(key) {
			writeError(w, http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			h.get(w, key)
		case http.MethodPut:
			h.put(w, r, key)
		case http.MethodDelete:
			h.delete(w, key)
		default:
			methodNotAllowed(w, http.MethodGet, http.MethodPut, http.MethodDelete)
		}

	default:
		writeError(w, http.StatusNotFound)
	}
}

func (h *Handler) list(w http.ResponseWriter) {
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		writeError(w, http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) get(w http.ResponseWriter, key string) {
	v, ok := h.store.Get(key)
	if !ok {
		writeError(w, http.StatusNotFound)
		return
	}
	writeBody(w, http.StatusOK, "application/octet-stream", v)
}

func (h *Handler) put(w http.ResponseWriter, r *http.Request, key string) {
	if r.ContentLength > MaxValueSize {
		writeError(w, http.StatusRequestEntityTooLarge)
		return
	}
	value, err := readBody(w, r)
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeError(w, http.StatusRequestEntityTooLarge)
		} else {
			writeError(w, http.StatusBadRequest)
		}
		return
	}
	status := http.StatusOK
	if h.store.Put(key, value) {
		status = http.StatusCreated
	}
	writeBody(w, status, "", nil)
}

func (h *Handler) delete(w http.ResponseWriter, key string) {
	if !h.store.Delete(key) {
		writeError(w, http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// readBody reads the request body, enforcing MaxValueSize.
func readBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	body := http.MaxBytesReader(w, r.Body, MaxValueSize)
	if r.ContentLength >= 0 {
		buf := make([]byte, r.ContentLength)
		if _, err := io.ReadFull(body, buf); err != nil {
			return nil, err
		}
		return buf, nil
	}
	return io.ReadAll(body)
}

// rawPath returns the path component of the request target exactly as sent.
func rawPath(r *http.Request) string {
	p := r.RequestURI
	if i := strings.IndexByte(p, '?'); i >= 0 {
		p = p[:i]
	}
	if p == "" || p[0] != '/' {
		// Absolute-form or other unusual targets: fall back to the parsed URL.
		p = r.URL.EscapedPath()
	}
	return p
}

func validKey(key string) bool {
	if len(key) == 0 || len(key) > maxKeyLen {
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

func methodNotAllowed(w http.ResponseWriter, allowed ...string) {
	w.Header().Set("Allow", strings.Join(allowed, ", "))
	writeError(w, http.StatusMethodNotAllowed)
}

func writeError(w http.ResponseWriter, status int) {
	writeBody(w, status, "text/plain; charset=utf-8", []byte(http.StatusText(status)))
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
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
