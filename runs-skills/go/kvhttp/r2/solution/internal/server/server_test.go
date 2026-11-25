package server

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"kvhttp/internal/store"
)

func do(t *testing.T, h http.Handler, method, path string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	t.Parallel()
	h := New(store.New())
	long := strings.Repeat("k", 64)
	steps := []struct {
		method, path, body string
		status             int
		want               string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/health/", "", 404, ""},
		{"GET", "/", "", 404, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"PUT", "/kv", "", 405, ""},
		{"PUT", "/kv/b", "2", 201, ""},
		{"PUT", "/kv/" + long, "x", 201, ""},
		{"PUT", "/kv/" + long + "k", "x", 400, ""},
		{"PUT", "/kv/A-_9", "", 201, ""},
		{"GET", "/kv/A-_9", "", 200, ""},
		{"PUT", "/kv/b", "22", 200, ""},
		{"GET", "/kv/b", "", 200, "22"},
		{"GET", "/kv", "", 200, `["A-_9","b","` + long + `"]`},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/a.b", "", 400, ""},
		{"PATCH", "/kv/b", "", 405, ""},
		{"DELETE", "/kv/b", "", 204, ""},
		{"DELETE", "/kv/b", "", 404, ""},
		{"GET", "/kv/b", "", 404, ""},
	}
	for _, s := range steps {
		rec := do(t, h, s.method, s.path, []byte(s.body))
		if rec.Code != s.status {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.path, rec.Code, s.status)
		}
		if s.want != "" && rec.Body.String() != s.want {
			t.Fatalf("%s %s: body %q, want %q", s.method, s.path, rec.Body.String(), s.want)
		}
	}
}

func TestValueSize(t *testing.T) {
	t.Parallel()
	h := New(store.New())
	max := bytes.Repeat([]byte{0xff}, MaxValueSize)
	if rec := do(t, h, "PUT", "/kv/big", max); rec.Code != http.StatusCreated {
		t.Fatalf("PUT 1 MiB: status %d", rec.Code)
	}
	if rec := do(t, h, "GET", "/kv/big", nil); !bytes.Equal(rec.Body.Bytes(), max) {
		t.Fatalf("GET 1 MiB: body differs (%d bytes)", rec.Body.Len())
	}
	if rec := do(t, h, "PUT", "/kv/big", append(max, 0)); rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("PUT 1 MiB + 1: status %d", rec.Code)
	}
}

func TestConcurrentPuts(t *testing.T) {
	t.Parallel()
	h := New(store.New())
	var wg sync.WaitGroup
	for i := range 64 {
		wg.Go(func() {
			do(t, h, "PUT", "/kv/k"+strings.Repeat("x", i), []byte("v"))
		})
	}
	wg.Wait()
	if got := len(h.store.Keys()); got != 64 {
		t.Fatalf("keys = %d, want 64", got)
	}
}
