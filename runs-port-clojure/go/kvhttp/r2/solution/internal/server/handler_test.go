package server

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"kvhttp/internal/store"
)

func do(t *testing.T, h http.Handler, method, target string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req := httptest.NewRequest(method, target, rd)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	h := New(store.New())
	big := bytes.Repeat([]byte{0xff}, MaxValueBytes)
	steps := []struct {
		method, path string
		body         []byte
		status       int
		want         string
	}{
		{"GET", "/health", nil, 200, "ok"},
		{"POST", "/health", nil, 405, ""},
		{"GET", "/health/", nil, 404, ""},
		{"GET", "/nope", nil, 404, ""},
		{"GET", "/kv", nil, 200, "[]"},
		{"POST", "/kv", nil, 405, ""},
		{"GET", "/kv/", nil, 400, ""},
		{"GET", "/kv/a/b", nil, 400, ""},
		{"GET", "/kv/bad.key", nil, 400, ""},
		{"GET", "/kv/%41", nil, 400, ""},
		{"GET", "/kv/" + strings.Repeat("a", 65), nil, 400, ""},
		{"PUT", "/kv/" + strings.Repeat("a", 64), []byte("x"), 201, ""},
		{"PUT", "/kv/b", []byte("1"), 201, ""},
		{"PUT", "/kv/b", []byte("2"), 200, ""},
		{"GET", "/kv/b", nil, 200, "2"},
		{"PATCH", "/kv/b", nil, 405, ""},
		{"PUT", "/kv/empty", nil, 201, ""},
		{"GET", "/kv/empty", nil, 200, ""},
		{"PUT", "/kv/big", big, 201, ""},
		{"GET", "/kv/big", nil, 200, string(big)},
		{"PUT", "/kv/huge", append(big, 0), 413, ""},
		{"GET", "/kv", nil, 200, `["` + strings.Repeat("a", 64) + `","b","big","empty"]`},
		{"DELETE", "/kv/b", nil, 204, ""},
		{"DELETE", "/kv/b", nil, 404, ""},
		{"GET", "/kv/b", nil, 404, ""},
	}
	for _, s := range steps {
		rec := do(t, h, s.method, s.path, s.body)
		if rec.Code != s.status {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.path, rec.Code, s.status)
		}
		if got := rec.Body.String(); got != s.want {
			t.Fatalf("%s %s: body %.40q, want %.40q", s.method, s.path, got, s.want)
		}
	}
}

func TestConcurrentPuts(t *testing.T) {
	h := New(store.New())
	var wg sync.WaitGroup
	var mu sync.Mutex
	created := 0
	for range 64 {
		wg.Go(func() {
			if do(t, h, "PUT", "/kv/same", []byte("v")).Code == http.StatusCreated {
				mu.Lock()
				created++
				mu.Unlock()
			}
		})
	}
	wg.Wait()
	if created != 1 {
		t.Fatalf("created %d times, want 1", created)
	}
}
