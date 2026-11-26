package api

import (
	"errors"
	"net/http"

	"notes/internal/store"
)

// handleCreateNote serves POST /notes.
func (s *Server) handleCreateNote(w http.ResponseWriter, r *http.Request) {
	in, err := decodeNoteInput(w, r)
	if err != nil {
		s.writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	n, err := s.store.Create(r.Context(), in)
	if err != nil {
		s.writeInternalError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusCreated, n)
}

// handleGetNote serves GET /notes/{id}.
func (s *Server) handleGetNote(w http.ResponseWriter, r *http.Request) {
	id, ok := s.noteID(w, r)
	if !ok {
		return
	}
	n, err := s.store.Get(r.Context(), id)
	if err != nil {
		s.writeStoreError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, n)
}

// noteID extracts the {id} path value. If it is not a positive integer it
// responds with 404 and returns ok == false.
func (s *Server) noteID(w http.ResponseWriter, r *http.Request) (id int64, ok bool) {
	id, ok = parseNoteID(r.PathValue("id"))
	if !ok {
		s.writeError(w, http.StatusNotFound, "note not found")
	}
	return id, ok
}

// writeStoreError maps store errors to responses: ErrNotFound becomes 404,
// anything else 500.
func (s *Server) writeStoreError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, store.ErrNotFound) {
		s.writeError(w, http.StatusNotFound, "note not found")
		return
	}
	s.writeInternalError(w, r, err)
}
