package server

import (
	"errors"
	"net/http"
	"net/url"
	"strconv"

	"notes/internal/note"
	"notes/internal/store"
)

// listResponse is the JSON body of GET /notes.
type listResponse struct {
	Notes []note.Note `json:"notes"`
}

// handleListNotes serves GET /notes.
func (s *Server) handleListNotes(w http.ResponseWriter, r *http.Request) {
	f, err := parseFilter(r.URL.Query())
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	notes, err := s.store.List(r.Context(), f)
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, listResponse{Notes: notes})
}

// parseFilter reads the tag, q, after and limit query parameters. Its errors are *requestError.
func parseFilter(q url.Values) (store.Filter, error) {
	f := store.Filter{Limit: store.MaxListLimit}
	if q.Has("tag") {
		tag := q.Get("tag")
		f.Tag = &tag
	}
	if q.Has("q") {
		text := q.Get("q")
		f.Query = &text
	}
	if q.Has("after") {
		after, err := strconv.ParseInt(q.Get("after"), 10, 64)
		// An integer beyond the int64 range is still a valid bound: ParseInt clamps it, which keeps
		// every note (very negative) or none (very positive).
		if err != nil && !errors.Is(err, strconv.ErrRange) {
			return store.Filter{}, badRequest("after must be an integer")
		}
		f.After = after
	}
	if q.Has("limit") {
		limit, err := strconv.Atoi(q.Get("limit"))
		if err != nil || limit < 1 || limit > store.MaxListLimit {
			return store.Filter{}, badRequest("limit must be an integer from 1 to %d", store.MaxListLimit)
		}
		f.Limit = limit
	}
	return f, nil
}
