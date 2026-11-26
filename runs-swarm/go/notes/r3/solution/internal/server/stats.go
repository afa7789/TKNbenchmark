package server

import (
	"net/http"

	"notes/internal/store"
)

// statsResponse is the body of GET /stats.
type statsResponse struct {
	Notes int64            `json:"notes"`
	Tags  map[string]int64 `json:"tags"`
}

// tagsResponse is the body of GET /tags.
type tagsResponse struct {
	Tags []store.TagCount `json:"tags"`
}

// handleStats serves GET /stats: the number of notes and the number of notes per tag.
func (s *Server) handleStats(w http.ResponseWriter, r *http.Request) {
	st, err := s.store.Stats(r.Context())
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	tags := make(map[string]int64, len(st.Tags))
	for _, tc := range st.Tags {
		tags[tc.Tag] = tc.Count
	}
	s.writeJSON(w, http.StatusOK, statsResponse{Notes: st.Notes, Tags: tags})
}

// handleTags serves GET /tags: every tag in use with its note count, by count descending, then tag
// ascending.
func (s *Server) handleTags(w http.ResponseWriter, r *http.Request) {
	counts, err := s.store.TagCounts(r.Context())
	if err != nil {
		s.writeErr(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, tagsResponse{Tags: counts})
}
