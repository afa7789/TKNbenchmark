package kv

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func do(t *testing.T, h http.Handler, method, target string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	req := httptest.NewRequest(method, target, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	h := NewHandler(NewStore())
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
		{"PUT", "/kv/empty", "", 201, ""},
		{"GET", "/kv/empty", "", 200, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"PATCH", "/kv/b", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/a%2Fb", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("x", 65), "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("x", 64), "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/health/", "", 404, ""},
	}
	for _, s := range steps {
		var body []byte
		if s.method == "PUT" {
			body = []byte(s.body)
		}
		rec := do(t, h, s.method, s.path, body)
		if rec.Code != s.status {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.path, rec.Code, s.status)
		}
		if got := rec.Body.String(); got != s.want {
			t.Fatalf("%s %s: body %q, want %q", s.method, s.path, got, s.want)
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := NewHandler(NewStore())
	max := bytes.Repeat([]byte{0xff}, MaxValueBytes)
	if rec := do(t, h, "PUT", "/kv/big", max); rec.Code != 201 {
		t.Fatalf("max-size value: status %d", rec.Code)
	}
	if rec := do(t, h, "GET", "/kv/big", nil); !bytes.Equal(rec.Body.Bytes(), max) {
		t.Fatal("max-size value not round-tripped")
	}
	if rec := do(t, h, "PUT", "/kv/big", append(max, 0)); rec.Code != 413 {
		t.Fatalf("oversized value: status %d, want 413", rec.Code)
	}
}
