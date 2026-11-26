package httpapi

import (
	"errors"
	"net/http"

	"notes/internal/store"
)

// handleCreate implements POST /notes.
func (s *Server) handleCreate(w http.ResponseWriter, r *http.Request) {
	in, ok := s.readInput(w, r)
	if !ok {
		return
	}
	n, err := s.store.Create(r.Context(), in)
	if err != nil {
		s.serverError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusCreated, n)
}

// handleGet implements GET /notes/{id}.
func (s *Server) handleGet(w http.ResponseWriter, r *http.Request) {
	id, ok := s.noteID(w, r)
	if !ok {
		return
	}
	n, err := s.store.Get(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		s.notFound(w)
		return
	}
	if err != nil {
		s.serverError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, n)
}
