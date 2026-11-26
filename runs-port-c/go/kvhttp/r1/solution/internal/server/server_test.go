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

func do(t *testing.T, h http.Handler, method, target, body string) *http.Response {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, target, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec.Result()
}

func TestRoutes(t *testing.T) {
	h := New(store.New())
	tests := []struct {
		method, target, body string
		wantStatus           int
		wantBody             string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"PUT", "/kv/b", "hello", 201, ""},
		{"PUT", "/kv/b", "world", 200, ""},
		{"PUT", "/kv/a", "", 201, ""},
		{"GET", "/kv/b", "", 200, "world"},
		{"GET", "/kv/a", "", 200, ""},
		{"GET", "/kv", "", 200, `["a","b"]`},
		{"PATCH", "/kv/a", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
	}
	for _, tc := range tests {
		res := do(t, h, tc.method, tc.target, tc.body)
		got, _ := io.ReadAll(res.Body)
		if res.StatusCode != tc.wantStatus || string(got) != tc.wantBody {
			t.Errorf("%s %s: got %d %q, want %d %q", tc.method, tc.target, res.StatusCode, got, tc.wantStatus, tc.wantBody)
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := New(store.New())
	max := string(bytes.Repeat([]byte{0xff}, MaxValueBytes))
	if res := do(t, h, "PUT", "/kv/big", max); res.StatusCode != 201 {
		t.Fatalf("1 MiB value: status %d", res.StatusCode)
	}
	if res := do(t, h, "PUT", "/kv/big", max+"x"); res.StatusCode != 413 {
		t.Fatalf("oversized value: status %d", res.StatusCode)
	}
}
