package httpapi

import (
	"net/http"
	"testing"
)

func TestHealth(t *testing.T) {
	url := newTestServer(t)
	status, body := do(t, http.MethodGet, url+"/health", "")
	if status != http.StatusOK || body != "ok" {
		t.Fatalf("GET /health = %d %q, want 200 \"ok\"", status, body)
	}
}

func TestCreateAndGet(t *testing.T) {
	url := newTestServer(t)

	status, body := do(t, http.MethodPost, url+"/notes", `{"title":"first"}`)
	if status != http.StatusCreated {
		t.Fatalf("POST status = %d, want 201 (%s)", status, body)
	}
	assertJSON(t, body, `{"id":1,"title":"first","body":"","tags":[]}`)

	status, body = do(t, http.MethodPost, url+"/notes", `{"title":"  second  ","body":"some text","tags":["work","b-2","work"]}`)
	if status != http.StatusCreated {
		t.Fatalf("POST status = %d, want 201 (%s)", status, body)
	}
	want := `{"id":2,"title":"second","body":"some text","tags":["b-2","work"]}`
	assertJSON(t, body, want)

	status, body = do(t, http.MethodGet, url+"/notes/2", "")
	if status != http.StatusOK {
		t.Fatalf("GET status = %d, want 200", status)
	}
	assertJSON(t, body, want)
}

func TestCreateInvalid(t *testing.T) {
	url := newTestServer(t)
	for _, body := range []string{
		`{"title": `, `[]`, `{}`, `{"title":"   "}`, `{"title":"x","tags":["Bad"]}`, `{"title":"x","body":3}`,
	} {
		status, resp := do(t, http.MethodPost, url+"/notes", body)
		if status != http.StatusBadRequest {
			t.Errorf("POST %s = %d, want 400", body, status)
			continue
		}
		assertError(t, resp)
	}
}

func TestNotFoundAndMethodNotAllowed(t *testing.T) {
	url := newTestServer(t)
	tests := []struct {
		method, path string
		status       int
	}{
		{http.MethodGet, "/nope", http.StatusNotFound},
		{http.MethodGet, "/notes/abc", http.StatusNotFound},
		{http.MethodGet, "/notes/0", http.StatusNotFound},
		{http.MethodGet, "/notes/-1", http.StatusNotFound},
		{http.MethodGet, "/notes/+1", http.StatusNotFound},
		{http.MethodGet, "/notes/99999999999999999999", http.StatusNotFound},
		{http.MethodGet, "/notes/7", http.StatusNotFound},
		{http.MethodDelete, "/notes", http.StatusMethodNotAllowed},
		{http.MethodPost, "/notes/1", http.StatusMethodNotAllowed},
		{http.MethodPost, "/health", http.StatusMethodNotAllowed},
	}
	for _, tt := range tests {
		status, body := do(t, tt.method, url+tt.path, "")
		if status != tt.status {
			t.Errorf("%s %s = %d, want %d", tt.method, tt.path, status, tt.status)
			continue
		}
		assertError(t, body)
	}
}
