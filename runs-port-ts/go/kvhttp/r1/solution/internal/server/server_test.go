package server

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"kvhttp/internal/store"
)

func do(t *testing.T, h http.Handler, method, target string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	h := New(store.New())
	long := strings.Repeat("a", 65)

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
		{"PUT", "/kv/empty", "", 201, ""},
		{"GET", "/kv/empty", "", 200, ""},
		{"GET", "/kv", "", 200, `["a","b","empty"]`},
		{"POST", "/kv", "", 405, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"PATCH", "/kv/a", "", 405, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + long, "", 400, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
	}
	for _, s := range steps {
		rec := do(t, h, s.method, s.path, []byte(s.body))
		if rec.Code != s.status {
			t.Errorf("%s %s: status %d, want %d", s.method, s.path, rec.Code, s.status)
		}
		if got := rec.Body.String(); got != s.want {
			t.Errorf("%s %s: body %q, want %q", s.method, s.path, got, s.want)
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := New(store.New())
	if rec := do(t, h, "PUT", "/kv/k", make([]byte, MaxValueBytes)); rec.Code != 201 {
		t.Fatalf("max-size value: status %d", rec.Code)
	}
	if rec := do(t, h, "PUT", "/kv/k2", make([]byte, MaxValueBytes+1)); rec.Code != 413 {
		t.Fatalf("oversize value: status %d", rec.Code)
	}
}
