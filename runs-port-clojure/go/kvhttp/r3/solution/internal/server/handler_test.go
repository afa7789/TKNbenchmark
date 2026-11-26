package server

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"kvhttp/internal/store"
)

func do(t *testing.T, h http.Handler, method, target, body string) (*http.Response, string) {
	t.Helper()
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, target, rd)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	res := rec.Result()
	b, _ := io.ReadAll(res.Body)
	return res, string(b)
}

func TestRoutes(t *testing.T) {
	h := New(store.New())
	long := strings.Repeat("k", 65)
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
		{"POST", "/kv", "", 405, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + long, "", 400, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/kv/" + long[:64], "", 404, ""},
	}
	for _, s := range steps {
		res, body := do(t, h, s.method, s.path, s.body)
		if res.StatusCode != s.status || (s.want != "" && body != s.want) {
			t.Errorf("%s %s: got %d %q, want %d %q", s.method, s.path, res.StatusCode, body, s.status, s.want)
		}
	}
}
