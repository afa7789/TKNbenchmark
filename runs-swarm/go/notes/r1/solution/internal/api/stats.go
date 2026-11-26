package api

import (
	"net/http"

	"notes/internal/store"
)

// Owned by the stats branch.

type statsResponse struct {
	Notes int64            `json:"notes"`
	Tags  map[string]int64 `json:"tags"`
}

type tagsResponse struct {
	Tags []store.TagCount `json:"tags"`
}

// handleStats serves GET /stats.
func (s *Server) handleStats(w http.ResponseWriter, r *http.Request) {
	st, err := s.store.Stats(r.Context())
	if err != nil {
		s.writeInternalError(w, r, err)
		return
	}
	resp := statsResponse{Notes: st.Notes, Tags: make(map[string]int64, len(st.Tags))}
	for _, tc := range st.Tags {
		resp.Tags[tc.Tag] = tc.Count
	}
	s.writeJSON(w, http.StatusOK, resp)
}

// handleTags serves GET /tags.
func (s *Server) handleTags(w http.ResponseWriter, r *http.Request) {
	st, err := s.store.Stats(r.Context())
	if err != nil {
		s.writeInternalError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, tagsResponse{Tags: st.Tags})
}
