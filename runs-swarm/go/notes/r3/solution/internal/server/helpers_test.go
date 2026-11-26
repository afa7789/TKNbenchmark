package server

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"notes/internal/note"
	"notes/internal/store"
)

// newTestServer returns a Server backed by a fresh database that is removed when the test ends.
func newTestServer(t *testing.T) *Server {
	t.Helper()
	st, err := store.Open(t.Context(), filepath.Join(t.TempDir(), "notes.db"))
	if err != nil {
		t.Fatalf("store.Open: %v", err)
	}
	t.Cleanup(func() { st.Close() })
	return New(st, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

// do sends a request with the given body ("" for none) and returns the recorded response.
func do(t *testing.T, s *Server, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequestWithContext(t.Context(), method, path, r)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	return rec
}

// wantStatus fails the test if rec does not have the given status.
func wantStatus(t *testing.T, rec *httptest.ResponseRecorder, status int) {
	t.Helper()
	if rec.Code != status {
		t.Fatalf("status = %d, want %d (body %q)", rec.Code, status, rec.Body.String())
	}
}

// wantJSON fails the test if rec is not a JSON response equal to want, which is decoded into a value of
// the same type as want.
func wantJSON[T any](t *testing.T, rec *httptest.ResponseRecorder, want T) {
	t.Helper()
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", ct)
	}
	var got T
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("body = %+v, want %+v", got, want)
	}
}

// wantError fails the test unless rec has the given status and a JSON {"error": ...} body.
func wantError(t *testing.T, rec *httptest.ResponseRecorder, status int) {
	t.Helper()
	wantStatus(t, rec, status)
	var body errorBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body.Error == "" {
		t.Errorf("error body = %q, want {\"error\": <message>}", rec.Body.String())
	}
}

// mustCreate creates a note through the API and returns it.
func mustCreate(t *testing.T, s *Server, body string) note.Note {
	t.Helper()
	rec := do(t, s, http.MethodPost, "/notes", body)
	wantStatus(t, rec, http.StatusCreated)
	var n note.Note
	if err := json.Unmarshal(rec.Body.Bytes(), &n); err != nil {
		t.Fatalf("decode created note %q: %v", rec.Body.String(), err)
	}
	return n
}
