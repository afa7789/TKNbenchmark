package server

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"kvhttp/internal/store"
)

func do(t *testing.T, h http.Handler, method, target string, body []byte) *http.Response {
	t.Helper()
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	req := httptest.NewRequest(method, target, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec.Result()
}

func TestRoutes(t *testing.T) {
	h := New(store.New())
	steps := []struct {
		method, target string
		body           string
		wantStatus     int
		wantBody       string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"PUT", "/kv/b", "2", 201, ""},
		{"PUT", "/kv/a", "1", 201, ""},
		{"PUT", "/kv/a", "one", 200, ""},
		{"GET", "/kv/a", "", 200, "one"},
		{"GET", "/kv", "", 200, `["a","b"]`},
		{"PATCH", "/kv/a", "", 405, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a.b", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"GET", "/nope", "", 404, ""},
	}
	for _, s := range steps {
		resp := do(t, h, s.method, s.target, []byte(s.body))
		got, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != s.wantStatus || string(got) != s.wantBody {
			t.Errorf("%s %s: got %d %q, want %d %q", s.method, s.target, resp.StatusCode, got, s.wantStatus, s.wantBody)
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := New(store.New())
	if resp := do(t, h, "PUT", "/kv/max", make([]byte, MaxValueBytes)); resp.StatusCode != 201 {
		t.Errorf("1 MiB value: status %d, want 201", resp.StatusCode)
	}
	if resp := do(t, h, "PUT", "/kv/over", make([]byte, MaxValueBytes+1)); resp.StatusCode != 413 {
		t.Errorf("oversized value: status %d, want 413", resp.StatusCode)
	}
}
