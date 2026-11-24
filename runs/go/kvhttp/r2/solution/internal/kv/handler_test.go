package kv

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
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
	long := strings.Repeat("k", MaxKeyLen)
	tests := []struct {
		method, path string
		body         []byte
		status       int
		want         string
	}{
		{"GET", "/health", nil, 200, "ok"},
		{"POST", "/health", nil, 405, ""},
		{"GET", "/health/", nil, 404, ""},
		{"GET", "/nope", nil, 404, ""},
		{"GET", "/", nil, 404, ""},
		{"GET", "/kv", nil, 200, "[]"},
		{"POST", "/kv", nil, 405, ""},
		{"PUT", "/kv/a", []byte("hello"), 201, ""},
		{"PUT", "/kv/a", []byte("world"), 200, ""},
		{"GET", "/kv/a", nil, 200, "world"},
		{"PATCH", "/kv/a", nil, 405, ""},
		{"PUT", "/kv/" + long, []byte(""), 201, ""},
		{"GET", "/kv/" + long, nil, 200, ""},
		{"GET", "/kv/" + long + "k", nil, 400, ""},
		{"GET", "/kv/", nil, 400, ""},
		{"GET", "/kv/a/b", nil, 400, ""},
		{"GET", "/kv/bad.key", nil, 400, ""},
		{"GET", "/kv/a%41", nil, 400, ""},
		{"GET", "/kv", nil, 200, fmt.Sprintf(`["a","%s"]`, long)},
		{"DELETE", "/kv/a", nil, 204, ""},
		{"DELETE", "/kv/a", nil, 404, ""},
		{"GET", "/kv/a", nil, 404, ""},
		{"PUT", "/kv/big", bytes.Repeat([]byte{0xff}, MaxValueSize), 201, ""},
		{"PUT", "/kv/big", bytes.Repeat([]byte{0}, MaxValueSize+1), 413, ""},
	}
	for _, tt := range tests {
		rec := do(t, h, tt.method, tt.path, tt.body)
		if rec.Code != tt.status {
			t.Errorf("%s %s: status %d, want %d", tt.method, tt.path, rec.Code, tt.status)
			continue
		}
		if tt.want != "" && rec.Body.String() != tt.want {
			t.Errorf("%s %s: body %q, want %q", tt.method, tt.path, rec.Body.String(), tt.want)
		}
	}
}

func TestConcurrentPuts(t *testing.T) {
	h := NewHandler(NewStore())
	const n = 128
	var wg sync.WaitGroup
	for i := range n {
		wg.Go(func() {
			if rec := do(t, h, "PUT", fmt.Sprintf("/kv/k%03d", i), []byte("v")); rec.Code != 201 {
				t.Errorf("put %d: status %d", i, rec.Code)
			}
		})
	}
	wg.Wait()
	if got := len(h.store.Keys()); got != n {
		t.Fatalf("got %d keys, want %d", got, n)
	}
}
