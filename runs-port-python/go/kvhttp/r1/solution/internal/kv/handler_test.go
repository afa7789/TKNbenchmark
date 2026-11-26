package kv

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func do(t *testing.T, h http.Handler, method, target string, body []byte) *http.Response {
	t.Helper()
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, target, r))
	return rec.Result()
}

func TestRoutes(t *testing.T) {
	h := NewHandler(NewStore())
	steps := []struct {
		method, target, body string
		status               int
		want                 string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"PUT", "/kv/b", "2", 201, ""},
		{"PUT", "/kv/a", "1", 201, ""},
		{"PUT", "/kv/a", "one", 200, ""},
		{"GET", "/kv/a", "", 200, "one"},
		{"GET", "/kv", "", 200, `["a","b"]`},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"PATCH", "/kv/b", "", 405, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
	}
	for _, s := range steps {
		var body []byte
		if s.body != "" {
			body = []byte(s.body)
		}
		res := do(t, h, s.method, s.target, body)
		got, _ := io.ReadAll(res.Body)
		if res.StatusCode != s.status || string(got) != s.want {
			t.Errorf("%s %s: got %d %q, want %d %q", s.method, s.target, res.StatusCode, got, s.status, s.want)
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := NewHandler(NewStore())
	if res := do(t, h, "PUT", "/kv/big", make([]byte, MaxValueBytes)); res.StatusCode != 201 {
		t.Fatalf("max-size value: status %d", res.StatusCode)
	}
	if res := do(t, h, "PUT", "/kv/big", make([]byte, MaxValueBytes+1)); res.StatusCode != 413 {
		t.Fatalf("oversized value: status %d", res.StatusCode)
	}
}
