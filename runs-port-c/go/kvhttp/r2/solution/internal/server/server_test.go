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

func TestRoutes(t *testing.T) {
	h := New(store.New())
	big := bytes.Repeat([]byte{0xff}, MaxValueSize)
	tests := []struct {
		method, target string
		body           []byte
		want           int
		wantBody       string
	}{
		{"GET", "/health", nil, 200, "ok"},
		{"POST", "/health", nil, 405, ""},
		{"GET", "/kv", nil, 200, "[]"},
		{"POST", "/kv", nil, 405, ""},
		{"GET", "/kv/a", nil, 404, ""},
		{"PUT", "/kv/a", []byte("hello"), 201, ""},
		{"PUT", "/kv/a", []byte("world"), 200, ""},
		{"GET", "/kv/a", nil, 200, "world"},
		{"PUT", "/kv/empty", nil, 201, ""},
		{"GET", "/kv/empty", nil, 200, ""},
		{"PUT", "/kv/big", big, 201, ""},
		{"PUT", "/kv/big", append(big, 0), 413, ""},
		{"GET", "/kv", nil, 200, `["a","big","empty"]`},
		{"PATCH", "/kv/a", nil, 405, ""},
		{"DELETE", "/kv/a", nil, 204, ""},
		{"DELETE", "/kv/a", nil, 404, ""},
		{"GET", "/kv/", nil, 400, ""},
		{"GET", "/kv/bad.key", nil, 400, ""},
		{"GET", "/kv/a/b", nil, 400, ""},
		{"GET", "/kv/%41", nil, 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), nil, 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), nil, 404, ""},
		{"GET", "/nope", nil, 404, ""},
		{"GET", "/", nil, 404, ""},
	}
	for _, tt := range tests {
		res := do(t, h, tt.method, tt.target, tt.body)
		got, _ := io.ReadAll(res.Body)
		if res.StatusCode != tt.want {
			t.Errorf("%s %s: status %d, want %d", tt.method, tt.target, res.StatusCode, tt.want)
		}
		if tt.wantBody != "" && string(got) != tt.wantBody {
			t.Errorf("%s %s: body %q, want %q", tt.method, tt.target, got, tt.wantBody)
		}
	}
	res := do(t, h, "GET", "/kv/big", nil)
	got, _ := io.ReadAll(res.Body)
	if !bytes.Equal(got, big) {
		t.Errorf("GET /kv/big returned %d bytes, want %d", len(got), len(big))
	}
	if ct := do(t, h, "GET", "/kv", nil).Header.Get("Content-Type"); ct != "application/json" {
		t.Errorf("list content-type %q", ct)
	}
}
