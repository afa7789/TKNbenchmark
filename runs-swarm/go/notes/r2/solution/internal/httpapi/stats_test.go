package httpapi

import (
	"net/http"
	"testing"
)

// seedStatsNotes creates notes with the given request bodies.
func seedStatsNotes(t *testing.T, url string, bodies ...string) {
	t.Helper()
	for _, b := range bodies {
		if status, resp := do(t, http.MethodPost, url+"/notes", b); status != http.StatusCreated {
			t.Fatalf("POST %s = %d %s", b, status, resp)
		}
	}
}

func TestStatsAndTags(t *testing.T) {
	url := newTestServer(t)

	status, body := do(t, http.MethodGet, url+"/stats", "")
	if status != http.StatusOK {
		t.Fatalf("GET /stats = %d, want 200", status)
	}
	assertJSON(t, body, `{"notes":0,"tags":{}}`)

	status, body = do(t, http.MethodGet, url+"/tags", "")
	if status != http.StatusOK {
		t.Fatalf("GET /tags = %d, want 200", status)
	}
	assertJSON(t, body, `{"tags":[]}`)

	seedStatsNotes(t, url,
		`{"title":"a","tags":["x","y","x"]}`,
		`{"title":"b","tags":["x","b"]}`,
		`{"title":"c","tags":["a"]}`,
		`{"title":"d"}`,
	)

	status, body = do(t, http.MethodGet, url+"/stats", "")
	if status != http.StatusOK {
		t.Fatalf("GET /stats = %d, want 200", status)
	}
	assertJSON(t, body, `{"notes":4,"tags":{"x":2,"y":1,"b":1,"a":1}}`)

	status, body = do(t, http.MethodGet, url+"/tags", "")
	if status != http.StatusOK {
		t.Fatalf("GET /tags = %d, want 200", status)
	}
	assertJSON(t, body, `{"tags":[{"tag":"x","count":2},{"tag":"a","count":1},{"tag":"b","count":1},{"tag":"y","count":1}]}`)
}

func TestStatsMethodNotAllowed(t *testing.T) {
	url := newTestServer(t)
	for _, path := range []string{"/stats", "/tags"} {
		status, body := do(t, http.MethodPost, url+path, "{}")
		if status != http.StatusMethodNotAllowed {
			t.Errorf("POST %s = %d, want 405", path, status)
			continue
		}
		assertError(t, body)
	}
}
