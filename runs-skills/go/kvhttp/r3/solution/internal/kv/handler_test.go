package kv

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandler(t *testing.T) {
	h := NewHandler(NewStore())
	steps := []struct {
		method, path, body string
		wantStatus         int
		wantBody           string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"PUT", "/kv/a", "hello", 201, ""},
		{"PUT", "/kv/a", "world", 200, ""},
		{"GET", "/kv/a", "", 200, "world"},
		{"PUT", "/kv/B-_9", "", 201, ""},
		{"GET", "/kv/B-_9", "", 200, ""},
		{"GET", "/kv", "", 200, `["B-_9","a"]`},
		{"PATCH", "/kv/a", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
		{"GET", "/kvx", "", 404, ""},
	}
	for _, s := range steps {
		req := httptest.NewRequest(s.method, s.path, strings.NewReader(s.body))
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != s.wantStatus {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.path, rec.Code, s.wantStatus)
		}
		if s.wantStatus < 300 && rec.Body.String() != s.wantBody {
			t.Fatalf("%s %s: body %q, want %q", s.method, s.path, rec.Body.String(), s.wantBody)
		}
	}
}

func TestPutTooLarge(t *testing.T) {
	h := NewHandler(NewStore())
	ok := bytes.Repeat([]byte{0xff}, MaxValueSize)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("PUT", "/kv/big", bytes.NewReader(ok)))
	if rec.Code != http.StatusCreated {
		t.Fatalf("1 MiB put: status %d", rec.Code)
	}
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("PUT", "/kv/big", bytes.NewReader(append(ok, 0))))
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized put: status %d", rec.Code)
	}
}
