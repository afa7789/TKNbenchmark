package server

import (
	"net/http"
	"strings"
	"testing"

	"notes/internal/note"
)

func TestHealth(t *testing.T) {
	s := newTestServer(t)
	rec := do(t, s, http.MethodGet, "/health", "")
	wantStatus(t, rec, http.StatusOK)
	if got := rec.Body.String(); got != "ok" {
		t.Errorf("body = %q, want ok", got)
	}
}

func TestCreateAndGet(t *testing.T) {
	s := newTestServer(t)

	rec := do(t, s, http.MethodPost, "/notes", `{"title":"first"}`)
	wantStatus(t, rec, http.StatusCreated)
	wantJSON(t, rec, note.Note{ID: 1, Title: "first", Body: "", Tags: []string{}})

	second := note.Note{ID: 2, Title: "second", Body: "some text", Tags: []string{"b-2", "work"}}
	rec = do(t, s, http.MethodPost, "/notes",
		`{"title":"  second  ","body":"some text","tags":["work","b-2","work"],"extra":1}`)
	wantStatus(t, rec, http.StatusCreated)
	wantJSON(t, rec, second)

	rec = do(t, s, http.MethodGet, "/notes/2", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, second)
}

func TestCreateNullOptionalFields(t *testing.T) {
	s := newTestServer(t)
	rec := do(t, s, http.MethodPost, "/notes", `{"title":"x","body":null,"tags":null}`)
	wantStatus(t, rec, http.StatusCreated)
	wantJSON(t, rec, note.Note{ID: 1, Title: "x", Body: "", Tags: []string{}})
}

func TestCreateErrors(t *testing.T) {
	tests := []struct {
		name, body string
	}{
		{"empty body", ``},
		{"truncated JSON", `{"title": `},
		{"trailing data", `{"title":"x"} {}`},
		{"array", `[]`},
		{"string", `"x"`},
		{"null", `null`},
		{"missing title", `{}`},
		{"null title", `{"title":null}`},
		{"blank title", `{"title":"   "}`},
		{"long title", `{"title":"` + strings.Repeat("a", note.MaxTitleLen+1) + `"}`},
		{"numeric title", `{"title":5}`},
		{"numeric body", `{"title":"x","body":3}`},
		{"tags not array", `{"title":"x","tags":"a"}`},
		{"numeric tag", `{"title":"x","tags":[1]}`},
		{"uppercase tag", `{"title":"x","tags":["Bad"]}`},
		{"empty tag", `{"title":"x","tags":[""]}`},
	}
	s := newTestServer(t)
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			wantError(t, do(t, s, http.MethodPost, "/notes", tt.body), http.StatusBadRequest)
		})
	}
	// Nothing was stored, so the next note still gets id 1.
	if n := mustCreate(t, s, `{"title":"ok"}`); n.ID != 1 {
		t.Errorf("id after failed creates = %d, want 1", n.ID)
	}
}

func TestGetNotFound(t *testing.T) {
	s := newTestServer(t)
	mustCreate(t, s, `{"title":"x"}`)
	for _, path := range []string{"/notes/abc", "/notes/0", "/notes/-1", "/notes/7", "/notes/99999999999999999999"} {
		t.Run(path, func(t *testing.T) {
			wantError(t, do(t, s, http.MethodGet, path, ""), http.StatusNotFound)
		})
	}
}

func TestRouting(t *testing.T) {
	s := newTestServer(t)
	tests := []struct {
		method, path string
		status       int
	}{
		{http.MethodGet, "/nope", http.StatusNotFound},
		{http.MethodGet, "/notes/1/extra", http.StatusNotFound},
		{http.MethodGet, "/notes/", http.StatusNotFound},
		{http.MethodDelete, "/notes", http.StatusMethodNotAllowed},
		{http.MethodPost, "/notes/1", http.StatusMethodNotAllowed},
		{http.MethodPost, "/health", http.StatusMethodNotAllowed},
		{http.MethodPost, "/stats", http.StatusMethodNotAllowed},
		{http.MethodPost, "/tags", http.StatusMethodNotAllowed},
	}
	for _, tt := range tests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			rec := do(t, s, tt.method, tt.path, "")
			wantError(t, rec, tt.status)
			if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
				t.Errorf("Content-Type = %q, want application/json", ct)
			}
			if tt.status == http.StatusMethodNotAllowed && rec.Header().Get("Allow") == "" {
				t.Error("405 response has no Allow header")
			}
		})
	}
}
