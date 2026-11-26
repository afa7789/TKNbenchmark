package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func do(t *testing.T, h http.Handler, method, target string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, bytes.NewReader(body))
	if body == nil {
		req.ContentLength = 0
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	h := NewServer(NewStore())
	steps := []struct {
		method, target, body string
		wantStatus           int
		wantBody             string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"PUT", "/kv/b", "2", 201, ""},
		{"PUT", "/kv/a", "1", 201, ""},
		{"PUT", "/kv/a", "one", 200, ""},
		{"GET", "/kv/a", "", 200, "one"},
		{"GET", "/kv", "", 200, `["a","b"]`},
		{"DELETE", "/kv/b", "", 204, ""},
		{"DELETE", "/kv/b", "", 404, ""},
		{"GET", "/kv/b", "", 404, ""},
		{"PATCH", "/kv/a", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), "", 404, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/kvx", "", 404, ""},
	}
	for _, s := range steps {
		var body []byte
		if s.body != "" {
			body = []byte(s.body)
		}
		rec := do(t, h, s.method, s.target, body)
		if rec.Code != s.wantStatus {
			t.Errorf("%s %s: status %d, want %d", s.method, s.target, rec.Code, s.wantStatus)
		}
		if got := rec.Body.String(); got != s.wantBody {
			t.Errorf("%s %s: body %q, want %q", s.method, s.target, got, s.wantBody)
		}
	}
}

func TestValueSizeLimit(t *testing.T) {
	h := NewServer(NewStore())
	if rec := do(t, h, "PUT", "/kv/big", make([]byte, maxValueSize)); rec.Code != 201 {
		t.Fatalf("1 MiB value: status %d, want 201", rec.Code)
	}
	if rec := do(t, h, "PUT", "/kv/big", make([]byte, maxValueSize+1)); rec.Code != 413 {
		t.Fatalf("oversized value: status %d, want 413", rec.Code)
	}
}
