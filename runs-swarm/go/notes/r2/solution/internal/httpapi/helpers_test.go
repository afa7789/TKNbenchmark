package httpapi

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"notes/internal/store"
)

// newTestServer starts the API on a fresh database and returns its base URL.
func newTestServer(t *testing.T) string {
	t.Helper()
	st, err := store.Open(context.Background(), filepath.Join(t.TempDir(), "notes.db"))
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	ts := httptest.NewServer(New(st, slog.New(slog.DiscardHandler)))
	t.Cleanup(func() {
		ts.Close()
		st.Close()
	})
	return ts.URL
}

// do sends a request with an optional body and returns the status and body.
func do(t *testing.T, method, url, body string) (int, string) {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, url, r)
	if err != nil {
		t.Fatal(err)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, string(data)
}

// assertJSON fails unless got and want are equal JSON documents.
func assertJSON(t *testing.T, got, want string) {
	t.Helper()
	var g, w any
	if err := json.Unmarshal([]byte(got), &g); err != nil {
		t.Fatalf("response is not JSON: %q", got)
	}
	if err := json.Unmarshal([]byte(want), &w); err != nil {
		t.Fatalf("bad expectation %q: %v", want, err)
	}
	gb, _ := json.Marshal(g)
	wb, _ := json.Marshal(w)
	if string(gb) != string(wb) {
		t.Errorf("body = %s, want %s", gb, wb)
	}
}

// assertError fails unless body is a JSON {"error": "..."} object.
func assertError(t *testing.T, body string) {
	t.Helper()
	var e errorBody
	if err := json.Unmarshal([]byte(body), &e); err != nil || e.Error == "" {
		t.Errorf("body %q is not a JSON error", body)
	}
}
