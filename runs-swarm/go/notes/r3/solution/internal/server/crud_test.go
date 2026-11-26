package server

import (
	"net/http"
	"testing"

	"notes/internal/note"
)

func TestReplaceNote(t *testing.T) {
	s := newTestServer(t)
	mustCreate(t, s, `{"title":"old","body":"text","tags":["x"]}`)

	want := note.Note{ID: 1, Title: "new", Body: "", Tags: []string{"a", "b"}}
	rec := do(t, s, http.MethodPut, "/notes/1", `{"title":"  new ","tags":["b","a","b"]}`)
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, want)

	rec = do(t, s, http.MethodGet, "/notes/1", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, want)

	// Omitted (or null) body and tags are reset, not kept.
	rec = do(t, s, http.MethodPut, "/notes/1", `{"title":"t","body":null,"tags":null}`)
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, note.Note{ID: 1, Title: "t", Body: "", Tags: []string{}})
}

func TestReplaceNoteErrors(t *testing.T) {
	s := newTestServer(t)
	orig := mustCreate(t, s, `{"title":"keep","body":"b","tags":["k"]}`)

	for _, body := range []string{
		``, `{`, `[]`, `null`, `{}`, `{"title":""}`, `{"title":"  "}`, `{"title":1}`,
		`{"title":"x","body":2}`, `{"title":"x","tags":"a"}`, `{"title":"x","tags":["A"]}`,
	} {
		t.Run(body, func(t *testing.T) {
			wantError(t, do(t, s, http.MethodPut, "/notes/1", body), http.StatusBadRequest)
		})
	}
	// Failed replacements leave the note untouched.
	rec := do(t, s, http.MethodGet, "/notes/1", "")
	wantStatus(t, rec, http.StatusOK)
	wantJSON(t, rec, orig)

	for _, path := range []string{"/notes/9", "/notes/0", "/notes/-1", "/notes/abc"} {
		t.Run(path, func(t *testing.T) {
			wantError(t, do(t, s, http.MethodPut, path, `{"title":"none"}`), http.StatusNotFound)
		})
	}
}

func TestDeleteNote(t *testing.T) {
	s := newTestServer(t)
	mustCreate(t, s, `{"title":"a"}`)
	mustCreate(t, s, `{"title":"b"}`)

	rec := do(t, s, http.MethodDelete, "/notes/2", "")
	wantStatus(t, rec, http.StatusNoContent)
	if rec.Body.Len() != 0 {
		t.Errorf("body = %q, want empty", rec.Body.String())
	}
	wantError(t, do(t, s, http.MethodGet, "/notes/2", ""), http.StatusNotFound)
	wantError(t, do(t, s, http.MethodDelete, "/notes/2", ""), http.StatusNotFound)
	wantError(t, do(t, s, http.MethodPut, "/notes/2", `{"title":"x"}`), http.StatusNotFound)
	wantStatus(t, do(t, s, http.MethodGet, "/notes/1", ""), http.StatusOK)

	for _, path := range []string{"/notes/0", "/notes/-1", "/notes/abc", "/notes/99"} {
		t.Run(path, func(t *testing.T) {
			wantError(t, do(t, s, http.MethodDelete, path, ""), http.StatusNotFound)
		})
	}

	// The id of a deleted note is not reused.
	if n := mustCreate(t, s, `{"title":"c"}`); n.ID != 3 {
		t.Errorf("id after delete = %d, want 3", n.ID)
	}
}
