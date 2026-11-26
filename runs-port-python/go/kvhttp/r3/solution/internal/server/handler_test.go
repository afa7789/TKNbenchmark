package server

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
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	h := NewHandler(NewStore())
	big := bytes.Repeat([]byte{0xff, 0x00}, MaxValueBytes/2)
	steps := []struct {
		method, target string
		body           []byte
		status         int
		want           string
	}{
		{"GET", "/health", nil, 200, "ok"},
		{"POST", "/health", nil, 405, ""},
		{"GET", "/kv", nil, 200, "[]"},
		{"PUT", "/kv/" + strings.Repeat("a", 64), []byte("v"), 201, ""},
		{"PUT", "/kv/" + strings.Repeat("a", 65), []byte("v"), 400, ""},
		{"GET", "/kv/", nil, 400, ""},
		{"GET", "/kv/a/b", nil, 400, ""},
		{"GET", "/kv/%41", nil, 400, ""},
		{"PUT", "/kv/big", big, 201, ""},
		{"PUT", "/kv/big", append(big, 1), 413, ""},
		{"GET", "/kv/big", nil, 200, string(big)},
		{"PUT", "/kv/B-_9", nil, 201, ""},
		{"GET", "/kv/B-_9", nil, 200, ""},
		{"GET", "/kv", nil, 200, `["B-_9","` + strings.Repeat("a", 64) + `","big"]`},
		{"POST", "/kv", nil, 405, ""},
		{"PATCH", "/kv/x", nil, 405, ""},
		{"DELETE", "/kv/big", nil, 204, ""},
		{"DELETE", "/kv/big", nil, 404, ""},
		{"GET", "/kvx", nil, 404, ""},
		{"GET", "/", nil, 404, ""},
	}
	for _, s := range steps {
		rec := do(t, h, s.method, s.target, s.body)
		if rec.Code != s.status {
			t.Errorf("%s %s: status %d, want %d", s.method, s.target, rec.Code, s.status)
		}
		if s.want != "" && rec.Body.String() != s.want {
			t.Errorf("%s %s: body mismatch (%d bytes)", s.method, s.target, rec.Body.Len())
		}
	}
}
