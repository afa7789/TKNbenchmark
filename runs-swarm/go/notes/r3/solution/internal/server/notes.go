package server

import (
	"net/http"

	"notes/internal/note"
)

// noteRequest is the JSON body of POST /notes and PUT /notes/{id}. Pointers tell an omitted (or null)
// field from an empty one.
type noteRequest struct {
	Title *string   `json:"title"`
	Body  *string   `json:"body"`
	Tags  *[]string `json:"tags"`
}

// decodeNoteInput reads and normalizes a note body. An omitted body or tags field becomes "" or []. Its
// errors (*requestError or *note.ValidationError) are answered with 400 by writeErr.
func decodeNoteInput(w http.ResponseWriter, r *http.Request) (note.Input, error) {
	var req noteRequest
	if err := decodeJSON(w, r, &req); err != nil {
		return note.Input{}, err
	}
	return req.input().Normalize()
}

func (req noteRequest) input() note.Input {
	var in note.Input
	if req.Title != nil {
		in.Title = *req.Title
	}
	if req.Body != nil {
		in.Body = *req.Body
	}
	if req.Tags != nil {
		in.Tags = *req.Tags
	}
	return in
}

func (s *Server) handleCreateNote(w http.ResponseWriter, r *http.Request) {
	in, err := decodeNoteInput(w, r)
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	n, err := s.store.Create(r.Context(), in)
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusCreated, n)
}

func (s *Server) handleGetNote(w http.ResponseWriter, r *http.Request) {
	id, ok := noteID(r)
	if !ok {
		s.writeNotFound(w)
		return
	}
	n, err := s.store.Get(r.Context(), id)
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, n)
}
