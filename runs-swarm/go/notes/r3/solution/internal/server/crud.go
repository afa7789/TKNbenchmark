package server

import "net/http"

// handleReplaceNote serves PUT /notes/{id}: a full replacement, so an omitted body or tags becomes "" or [].
func (s *Server) handleReplaceNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(r)
	if !ok {
		s.writeNotFound(w)
		return
	}
	in, err := decodeNoteInput(w, r)
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	n, err := s.store.Replace(r.Context(), id, in)
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, n)
}

// handleDeleteNote serves DELETE /notes/{id}.
func (s *Server) handleDeleteNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(r)
	if !ok {
		s.writeNotFound(w)
		return
	}
	if err := s.store.Delete(r.Context(), id); err != nil {
		s.writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
