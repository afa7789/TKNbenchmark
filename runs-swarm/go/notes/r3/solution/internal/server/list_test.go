package server

import (
	"net/http"
	"testing"

	"notes/internal/note"
)

func TestListNotes(t *testing.T) {
	s := newTestServer(t)

	rec := do(t, s, http.MethodGet, "/notes", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, listResponse{Notes: []note.Note{}})
	if got := rec.Body.String(); got != "{\"notes\":[]}\n" {
		t.Errorf("empty list body = %q, want {\"notes\":[]}", got)
	}

	a := mustCreate(t, s, `{"title":"Hello world","tags":["greet"]}`)
	b := mustCreate(t, s, `{"title":"shopping","body":"milk","tags":["misc"]}`)
	c := mustCreate(t, s, `{"title":"other","body":"HELLO there","tags":["misc"]}`)

	tests := []struct {
		path string
		want []note.Note
	}{
		{"/notes", []note.Note{a, b, c}},
		{"/notes?tag=misc", []note.Note{b, c}},
		{"/notes?tag=Misc", []note.Note{}},
		{"/notes?q=hello", []note.Note{a, c}},
		{"/notes?q=HELLO%20W", []note.Note{a}},
		{"/notes?q=hello&tag=misc", []note.Note{c}},
		{"/notes?after=1", []note.Note{b, c}},
		{"/notes?after=0", []note.Note{a, b, c}},
		{"/notes?after=-1", []note.Note{a, b, c}},
		{"/notes?after=99999999999999999999", []note.Note{}},
		{"/notes?after=-99999999999999999999", []note.Note{a, b, c}},
		{"/notes?limit=2", []note.Note{a, b}},
		{"/notes?limit=100", []note.Note{a, b, c}},
		{"/notes?after=1&limit=1", []note.Note{b}},
		{"/notes?tag=misc&q=o&after=2&limit=1", []note.Note{c}},
	}
	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			rec := do(t, s, http.MethodGet, tt.path, "")
			wantStatus(t, rec, http.StatusOK)
			wantJSON(t, rec, listResponse{Notes: tt.want})
		})
	}
}

func TestListNotesErrors(t *testing.T) {
	s := newTestServer(t)
	mustCreate(t, s, `{"title":"x"}`)
	for _, query := range []string{
		"limit=0", "limit=101", "limit=-1", "limit=abc", "limit=", "limit=1.5", "limit=99999999999999999999",
		"after=abc", "after=", "after=1.5", "after=1e3",
	} {
		t.Run(query, func(t *testing.T) {
			wantError(t, do(t, s, http.MethodGet, "/notes?"+query, ""), http.StatusBadRequest)
		})
	}
}
