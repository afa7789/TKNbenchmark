package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"kvhttp/internal/store"
)

func TestRoutes(t *testing.T) {
	h := newServer(store.New())
	steps := []struct {
		method, path, body string
		status             int
		want               string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a.b", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("a", 65), "", 400, ""},
		{"PUT", "/kv/b", "2", 201, ""},
		{"PUT", "/kv/a", "1", 201, ""},
		{"PUT", "/kv/a", "x", 200, ""},
		{"GET", "/kv/a", "", 200, "x"},
		{"PATCH", "/kv/a", "", 405, ""},
		{"GET", "/kv", "", 200, `["a","b"]`},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"PUT", "/kv/big", strings.Repeat("z", maxValueBytes+1), 413, ""},
	}
	for _, s := range steps {
		req := httptest.NewRequest(s.method, s.path, strings.NewReader(s.body))
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != s.status {
			t.Errorf("%s %s: status %d, want %d", s.method, s.path, rec.Code, s.status)
		}
		if got := rec.Body.String(); got != s.want {
			t.Errorf("%s %s: body %q, want %q", s.method, s.path, got, s.want)
		}
	}
}

func TestListEmpty(t *testing.T) {
	rec := httptest.NewRecorder()
	newServer(store.New()).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/kv", nil))
	if rec.Body.String() != "[]" || rec.Header().Get("Content-Type") != "application/json" {
		t.Fatalf("got %q (%s)", rec.Body.String(), rec.Header().Get("Content-Type"))
	}
}
