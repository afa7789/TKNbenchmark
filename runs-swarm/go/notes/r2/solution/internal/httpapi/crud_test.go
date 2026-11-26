package httpapi

import (
	"net/http"
	"testing"
)

func TestUpdateNote(t *testing.T) {
	url := newTestServer(t)
	if status, body := do(t, http.MethodPost, url+"/notes", `{"title":"old","body":"text","tags":["x"]}`); status != http.StatusCreated {
		t.Fatalf("POST = %d %s", status, body)
	}

	status, body := do(t, http.MethodPut, url+"/notes/1", `{"title":"  new ","tags":["b","a","b"]}`)
	if status != http.StatusOK {
		t.Fatalf("PUT = %d %s, want 200", status, body)
	}
	want := `{"id":1,"title":"new","body":"","tags":["a","b"]}`
	assertJSON(t, body, want)
	_, body = do(t, http.MethodGet, url+"/notes/1", "")
	assertJSON(t, body, want)

	tests := []struct {
		name, path, body string
		status           int
	}{
		{"missing note", "/notes/9", `{"title":"none"}`, http.StatusNotFound},
		{"invalid id", "/notes/abc", `{"title":"x"}`, http.StatusNotFound},
		{"zero id", "/notes/0", `{"title":"x"}`, http.StatusNotFound},
		{"empty title", "/notes/1", `{"title":""}`, http.StatusBadRequest},
		{"missing title", "/notes/1", `{"body":"b"}`, http.StatusBadRequest},
		{"not an object", "/notes/1", `["title"]`, http.StatusBadRequest},
		{"invalid JSON", "/notes/1", `{"title":`, http.StatusBadRequest},
		{"body not a string", "/notes/1", `{"title":"x","body":1}`, http.StatusBadRequest},
		{"invalid tag", "/notes/1", `{"title":"x","tags":["A"]}`, http.StatusBadRequest},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			status, body := do(t, http.MethodPut, url+tt.path, tt.body)
			if status != tt.status {
				t.Fatalf("PUT %s %s = %d, want %d", tt.path, tt.body, status, tt.status)
			}
			assertError(t, body)
		})
	}

	// Failed updates leave the note unchanged.
	_, body = do(t, http.MethodGet, url+"/notes/1", "")
	assertJSON(t, body, want)
}

func TestDeleteNote(t *testing.T) {
	url := newTestServer(t)
	for _, title := range []string{"a", "b"} {
		if status, body := do(t, http.MethodPost, url+"/notes", `{"title":"`+title+`"}`); status != http.StatusCreated {
			t.Fatalf("POST = %d %s", status, body)
		}
	}

	status, body := do(t, http.MethodDelete, url+"/notes/1", "")
	if status != http.StatusNoContent || body != "" {
		t.Fatalf("DELETE = %d %q, want 204 with empty body", status, body)
	}
	for _, req := range [][2]string{
		{http.MethodGet, "/notes/1"},
		{http.MethodDelete, "/notes/1"},
		{http.MethodPut, "/notes/1"},
		{http.MethodDelete, "/notes/abc"},
		{http.MethodDelete, "/notes/-2"},
	} {
		status, body := do(t, req[0], url+req[1], `{"title":"x"}`)
		if status != http.StatusNotFound {
			t.Errorf("%s %s = %d, want 404", req[0], req[1], status)
			continue
		}
		assertError(t, body)
	}

	status, body = do(t, http.MethodPost, url+"/notes", `{"title":"c"}`)
	if status != http.StatusCreated {
		t.Fatalf("POST = %d %s", status, body)
	}
	assertJSON(t, body, `{"id":3,"title":"c","body":"","tags":[]}`)
}
