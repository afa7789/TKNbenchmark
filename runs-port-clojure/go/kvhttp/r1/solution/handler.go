package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
)

// maxBody is the largest accepted request body: 1 MiB values plus generous headroom.
const maxBody = 8 << 20

var keyPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// Handler serves the kvhttp routes backed by a Store.
type Handler struct {
	store *Store
}

// NewHandler returns an http.Handler backed by store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Route on the raw request path so percent-encoded bytes are not
	// silently decoded into otherwise valid (or path-separating) characters.
	path, _, _ := strings.Cut(r.RequestURI, "?")
	switch {
	case path == "/health":
		h.health(w, r)
	case path == "/kv":
		h.listKeys(w, r)
	case strings.HasPrefix(path, "/kv/"):
		h.item(w, r, strings.TrimPrefix(path, "/kv/"))
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, "GET")
		return
	}
	writeBody(w, http.StatusOK, "text/plain; charset=utf-8", []byte("ok"))
}

func (h *Handler) listKeys(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, "GET")
		return
	}
	body, err := json.Marshal(h.store.Keys())
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	writeBody(w, http.StatusOK, "application/json", body)
}

func (h *Handler) item(w http.ResponseWriter, r *http.Request, key string) {
	if !keyPattern.MatchString(key) {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	switch r.Method {
	case http.MethodGet:
		v, ok := h.store.Get(key)
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		writeBody(w, http.StatusOK, "application/octet-stream", v)
	case http.MethodPut:
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBody))
		if err != nil {
			var tooLarge *http.MaxBytesError
			if errors.As(err, &tooLarge) {
				w.WriteHeader(http.StatusRequestEntityTooLarge)
			} else {
				w.WriteHeader(http.StatusBadRequest)
			}
			return
		}
		if h.store.Put(key, body) {
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

func methodNotAllowed(w http.ResponseWriter, allowed string) {
	w.Header().Set("Allow", allowed)
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func writeBody(w http.ResponseWriter, status int, contentType string, body []byte) {
	hdr := w.Header()
	hdr.Set("Content-Type", contentType)
	hdr.Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		log.Printf("write response: %v", err)
	}
}
