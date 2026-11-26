package server

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"kvhttp/internal/store"
)

func do(t *testing.T, h http.Handler, method, target, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, strings.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	h := New(store.New())
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
		{"POST", "/kv", "", 405, ""},
		{"PATCH", "/kv/a", "", 405, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/kv/a/", "", 400, ""},
	}
	for _, s := range steps {
		rec := do(t, h, s.method, s.target, s.body)
		if rec.Code != s.status || rec.Body.String() != s.want {
			t.Errorf("%s %s = %d %q, want %d %q", s.method, s.target, rec.Code, rec.Body, s.status, s.want)
		}
	}
}

func TestBinaryValue(t *testing.T) {
	h := New(store.New())
	val := bytes.Repeat([]byte{0, 0xff, 'x', '\n'}, MaxValueLen/4)
	req := httptest.NewRequest("PUT", "/kv/big", bytes.NewReader(val))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != 201 {
		t.Fatalf("PUT status %d", rec.Code)
	}
	rec = do(t, h, "GET", "/kv/big", "")
	if !bytes.Equal(rec.Body.Bytes(), val) {
		t.Fatal("value round trip mismatch")
	}

	req = httptest.NewRequest("PUT", "/kv/big", bytes.NewReader(append(val, 1)))
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized PUT status %d, want 413", rec.Code)
	}
}
