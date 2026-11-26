package httpapi

import (
	"errors"
	"net/http"

	"notes/internal/store"
)

// handleUpdate implements PUT /notes/{id}: full replacement of a note.
// An omitted body or tags field resets it to "" or [].
func (s *Server) handleUpdate(w http.ResponseWriter, r *http.Request) {
	id, ok := s.noteID(w, r)
	if !ok {
		return
	}
	in, ok := s.readInput(w, r)
	if !ok {
		return
	}
	n, err := s.store.Update(r.Context(), id, in)
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

// handleDelete implements DELETE /notes/{id}.
func (s *Server) handleDelete(w http.ResponseWriter, r *http.Request) {
	id, ok := s.noteID(w, r)
	if !ok {
		return
	}
	err := s.store.Delete(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		s.notFound(w)
		return
	}
	if err != nil {
		s.serverError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
