package server

import (
	"net/http"
	"testing"
)

func TestStatsAndTagsEmpty(t *testing.T) {
	s := newTestServer(t)

	rec := do(t, s, http.MethodGet, "/stats", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, map[string]any{"notes": 0.0, "tags": map[string]any{}})

	rec = do(t, s, http.MethodGet, "/tags", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, map[string]any{"tags": []any{}})
}

func TestStatsAndTags(t *testing.T) {
	s := newTestServer(t)
	mustCreate(t, s, `{"title":"a","tags":["x","y"]}`)
	mustCreate(t, s, `{"title":"b","tags":["x","x"]}`)
	mustCreate(t, s, `{"title":"c","tags":["w"]}`)
	mustCreate(t, s, `{"title":"d"}`)

	rec := do(t, s, http.MethodGet, "/stats", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, statsResponse{Notes: 4, Tags: map[string]int64{"w": 1, "x": 2, "y": 1}})

	type tagCount struct {
		Tag   string `json:"tag"`
		Count int64  `json:"count"`
	}
	rec = do(t, s, http.MethodGet, "/tags", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, struct {
		Tags []tagCount `json:"tags"`
	}{Tags: []tagCount{{"x", 2}, {"w", 1}, {"y", 1}}})
}
