package kv

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func do(t *testing.T, h http.Handler, method, target string, body []byte) *http.Response {
	t.Helper()
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	req := httptest.NewRequest(method, target, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec.Result()
}

func readAll(t *testing.T, resp *http.Response) string {
	t.Helper()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestRoutes(t *testing.T) {
	h := NewHandler(&Store{})
	steps := []struct {
		method, target, body string
		status               int
		want                 string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("a", 65), "", 400, ""},
		{"PUT", "/kv/" + strings.Repeat("a", 64), "x", 201, ""},
		{"PUT", "/kv/b", "2", 201, ""},
		{"PUT", "/kv/b", "3", 200, ""},
		{"GET", "/kv/b", "", 200, "3"},
		{"PATCH", "/kv/b", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"GET", "/kv", "", 200, `["` + strings.Repeat("a", 64) + `","b"]`},
		{"DELETE", "/kv/b", "", 204, ""},
		{"DELETE", "/kv/b", "", 404, ""},
		{"GET", "/kv/b", "", 404, ""},
		{"PUT", "/kv/empty", "", 201, ""},
		{"GET", "/kv/empty", "", 200, ""},
	}
	for _, s := range steps {
		resp := do(t, h, s.method, s.target, []byte(s.body))
		if resp.StatusCode != s.status {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.target, resp.StatusCode, s.status)
		}
		if got := readAll(t, resp); s.want != "" && got != s.want {
			t.Fatalf("%s %s: body %q, want %q", s.method, s.target, got, s.want)
		}
	}
}

func TestValueSizeLimit(t *testing.T) {
	h := NewHandler(&Store{})
	if resp := do(t, h, "PUT", "/kv/big", make([]byte, MaxValueBytes)); resp.StatusCode != 201 {
		t.Fatalf("1 MiB value: status %d, want 201", resp.StatusCode)
	}
	if resp := do(t, h, "PUT", "/kv/big", make([]byte, MaxValueBytes+1)); resp.StatusCode != 413 {
		t.Fatalf("oversized value: status %d, want 413", resp.StatusCode)
	}
}
