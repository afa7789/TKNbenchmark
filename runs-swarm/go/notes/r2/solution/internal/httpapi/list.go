package httpapi

import (
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"

	"notes/internal/note"
	"notes/internal/store"
)

type listResponse struct {
	Notes []note.Note `json:"notes"`
}

// handleList implements GET /notes with the tag, q, after and limit query parameters.
func (s *Server) handleList(w http.ResponseWriter, r *http.Request) {
	f, err := parseListFilter(r.URL.Query())
	if err != nil {
		s.writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	notes, err := s.store.List(r.Context(), f)
	if err != nil {
		s.serverError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, listResponse{Notes: notes})
}

// parseListFilter builds a store.ListFilter from the query parameters of
// GET /notes. When a parameter is repeated, the first value wins.
func parseListFilter(q url.Values) (store.ListFilter, error) {
	f := store.ListFilter{Limit: store.MaxListLimit}

	if q.Has("tag") {
		tag := q.Get("tag")
		f.Tag = &tag
	}
	f.Query = q.Get("q")

	if q.Has("after") {
		after, err := strconv.ParseInt(q.Get("after"), 10, 64)
		// An out-of-range integer is still an integer: ParseInt clamps it to
		// the nearest int64, which selects the same notes.
		if err != nil && !errors.Is(err, strconv.ErrRange) {
			return store.ListFilter{}, errors.New("after must be an integer")
		}
		f.After = after
	}

	if q.Has("limit") {
		limit, err := strconv.Atoi(q.Get("limit"))
		if err != nil || limit < 1 || limit > store.MaxListLimit {
			return store.ListFilter{}, fmt.Errorf("limit must be an integer from 1 to %d", store.MaxListLimit)
		}
		f.Limit = limit
	}

	return f, nil
}
