package main

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

func do(t *testing.T, h http.Handler, method, path string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, r))
	return rec
}

func TestRoutes(t *testing.T) {
	t.Parallel()
	h := NewServer(NewStore())
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
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"PATCH", "/kv/a", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("x", 65), "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("x", 64), "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
		{"GET", "/health/", "", 404, ""},
	}
	for _, s := range steps {
		var body []byte
		if s.body != "" {
			body = []byte(s.body)
		}
		rec := do(t, h, s.method, s.path, body)
		if rec.Code != s.status {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.path, rec.Code, s.status)
		}
		if s.want != "" && rec.Body.String() != s.want {
			t.Fatalf("%s %s: body %q, want %q", s.method, s.path, rec.Body.String(), s.want)
		}
	}
}

func TestValueSizeLimit(t *testing.T) {
	t.Parallel()
	h := NewServer(NewStore())
	if rec := do(t, h, "PUT", "/kv/big", make([]byte, maxValueSize)); rec.Code != 201 {
		t.Fatalf("1 MiB value: status %d, want 201", rec.Code)
	}
	if rec := do(t, h, "PUT", "/kv/big", make([]byte, maxValueSize+1)); rec.Code != 413 {
		t.Fatalf("oversized value: status %d, want 413", rec.Code)
	}
}

func TestConcurrentPuts(t *testing.T) {
	t.Parallel()
	h := NewServer(NewStore())
	var wg sync.WaitGroup
	for i := range 64 {
		wg.Go(func() {
			key := fmt.Sprintf("k%d", i)
			if rec := do(t, h, "PUT", "/kv/"+key, []byte(key)); rec.Code != 201 {
				t.Errorf("PUT %s: status %d", key, rec.Code)
			}
		})
	}
	wg.Wait()
	if n := len(h.store.Keys()); n != 64 {
		t.Fatalf("got %d keys, want 64", n)
	}
}
