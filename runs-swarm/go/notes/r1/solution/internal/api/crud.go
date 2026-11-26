package api

import "net/http"

// Owned by the crud branch.

// handleUpdateNote serves PUT /notes/{id}. The request replaces the whole
// note: an omitted body or tags becomes "" or [].
func (s *Server) handleUpdateNote(w http.ResponseWriter, r *http.Request) {
	id, ok := s.noteID(w, r)
	if !ok {
		return
	}
	in, err := decodeNoteInput(w, r)
	if err != nil {
		s.writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	n, err := s.store.Update(r.Context(), id, in)
	if err != nil {
		s.writeStoreError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, n)
}

// handleDeleteNote serves DELETE /notes/{id}.
func (s *Server) handleDeleteNote(w http.ResponseWriter, r *http.Request) {
	id, ok := s.noteID(w, r)
	if !ok {
		return
	}
	if err := s.store.Delete(r.Context(), id); err != nil {
		s.writeStoreError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
