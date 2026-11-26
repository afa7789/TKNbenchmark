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

func do(t *testing.T, h http.Handler, method, path string, body []byte) *http.Response {
	t.Helper()
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	req := httptest.NewRequest(method, path, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec.Result()
}

func TestRoutes(t *testing.T) {
	h := New(store.New())
	steps := []struct {
		method, path, body string
		status             int
		want               string
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
		{"GET", "/kv/" + strings.Repeat("x", 65), "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("x", 64), "", 404, ""},
		{"GET", "/nope", "", 404, ""},
	}
	for _, s := range steps {
		var body []byte
		if s.body != "" {
			body = []byte(s.body)
		}
		res := do(t, h, s.method, s.path, body)
		if res.StatusCode != s.status {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.path, res.StatusCode, s.status)
		}
		if s.want != "" {
			got, _ := io.ReadAll(res.Body)
			if string(got) != s.want {
				t.Fatalf("%s %s: body %q, want %q", s.method, s.path, got, s.want)
			}
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := New(store.New())
	if res := do(t, h, "PUT", "/kv/big", make([]byte, MaxValueBytes)); res.StatusCode != 201 {
		t.Fatalf("max-size value: status %d", res.StatusCode)
	}
	if res := do(t, h, "PUT", "/kv/big", make([]byte, MaxValueBytes+1)); res.StatusCode != 413 {
		t.Fatalf("oversized value: status %d", res.StatusCode)
	}
}
