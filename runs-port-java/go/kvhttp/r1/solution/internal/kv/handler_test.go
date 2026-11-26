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
	tests := []struct {
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
		{"PATCH", "/kv/a", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/a%2Fb", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"PATCH", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), "", 404, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
		{"GET", "/health/", "", 404, ""},
	}
	for _, tc := range tests {
		var body []byte
		if tc.body != "" {
			body = []byte(tc.body)
		}
		rec := do(t, h, tc.method, tc.target, body)
		if rec.Code != tc.status {
			t.Errorf("%s %s: status %d, want %d", tc.method, tc.target, rec.Code, tc.status)
		}
		if got := rec.Body.String(); got != tc.want {
			t.Errorf("%s %s: body %q, want %q", tc.method, tc.target, got, tc.want)
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := NewHandler(NewStore())
	value := bytes.Repeat([]byte{0xff, 0x00}, MaxValueBytes/2)
	if rec := do(t, h, "PUT", "/kv/big", value); rec.Code != 201 {
		t.Fatalf("PUT 1 MiB: status %d", rec.Code)
	}
	if rec := do(t, h, "GET", "/kv/big", nil); !bytes.Equal(rec.Body.Bytes(), value) {
		t.Fatalf("GET 1 MiB: body differs (%d bytes)", rec.Body.Len())
	}
	if rec := do(t, h, "PUT", "/kv/big", append(value, 1)); rec.Code != 413 {
		t.Fatalf("PUT over limit: status %d, want 413", rec.Code)
	}
}
