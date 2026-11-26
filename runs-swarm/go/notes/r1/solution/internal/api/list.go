package api

import (
	"net/http"
	"net/url"
	"strconv"

	"notes/internal/store"
)

// Owned by the list branch.

const (
	defaultListLimit = 100
	maxListLimit     = 100
)

type listResponse struct {
	Notes []store.Note `json:"notes"`
}

// handleListNotes serves GET /notes?tag=&q=&after=&limit=.
func (s *Server) handleListNotes(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	f, err := parseListFilter(query)
	if err != nil {
		s.writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	notes := []store.Note{}
	// No stored note can have an invalid tag (including ""), so such a
	// filter matches nothing.
	if !query.Has("tag") || ValidTag(f.Tag) {
		notes, err = s.store.List(r.Context(), f)
		if err != nil {
			s.writeInternalError(w, r, err)
			return
		}
	}
	s.writeJSON(w, http.StatusOK, listResponse{Notes: notes})
}

// parseListFilter reads the GET /notes query parameters. Only limit and
// after can be invalid; a returned error is an errBadRequest.
func parseListFilter(q url.Values) (store.ListFilter, error) {
	f := store.ListFilter{
		Tag:   q.Get("tag"),
		Query: q.Get("q"),
		Limit: defaultListLimit,
	}
	if q.Has("after") {
		after, err := strconv.ParseInt(q.Get("after"), 10, 64)
		if err != nil {
			return f, badRequest("after must be an integer")
		}
		f.After = after
	}
	if q.Has("limit") {
		limit, err := strconv.Atoi(q.Get("limit"))
		if err != nil || limit < 1 || limit > maxListLimit {
			return f, badRequest("limit must be an integer from 1 to %d", maxListLimit)
		}
		f.Limit = limit
	}
	return f, nil
}
