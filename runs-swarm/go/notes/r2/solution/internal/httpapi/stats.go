package httpapi

import "net/http"

type statsResponse struct {
	Notes int64            `json:"notes"`
	Tags  map[string]int64 `json:"tags"`
}

// tagCount has the fields of store.TagCount, so one converts to the other.
type tagCount struct {
	Tag   string `json:"tag"`
	Count int64  `json:"count"`
}

type tagsResponse struct {
	Tags []tagCount `json:"tags"`
}

// handleStats implements GET /stats.
func (s *Server) handleStats(w http.ResponseWriter, r *http.Request) {
	st, err := s.store.Stats(r.Context())
	if err != nil {
		s.serverError(w, r, err)
		return
	}
	s.writeJSON(w, http.StatusOK, statsResponse{Notes: st.Notes, Tags: st.Tags})
}

// handleTags implements GET /tags.
func (s *Server) handleTags(w http.ResponseWriter, r *http.Request) {
	counts, err := s.store.TagCounts(r.Context())
	if err != nil {
		s.serverError(w, r, err)
		return
	}
	resp := tagsResponse{Tags: make([]tagCount, len(counts))}
	for i, tc := range counts {
		resp.Tags[i] = tagCount(tc)
	}
	s.writeJSON(w, http.StatusOK, resp)
}
