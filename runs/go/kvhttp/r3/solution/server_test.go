package main

import (
	"bytes"
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
	req := httptest.NewRequest(method, path, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRoutes(t *testing.T) {
	h := NewServer(NewStore())
	long := strings.Repeat("a", 64)
	tests := []struct {
		method, path, body string
		status             int
		want               string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/health/", "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/" + long + "a", "", 400, ""},
		{"PUT", "/kv/" + long, "x", 201, ""},
		{"GET", "/kv/" + long, "", 200, "x"},
		{"PUT", "/kv/a", "", 201, ""},
		{"GET", "/kv/a", "", 200, ""},
		{"PUT", "/kv/a", "v", 200, ""},
		{"PATCH", "/kv/a", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"GET", "/kv", "", 200, `["a","` + long + `"]`},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
	}
	for _, tt := range tests {
		rec := do(t, h, tt.method, tt.path, []byte(tt.body))
		if rec.Code != tt.status {
			t.Errorf("%s %s: status %d, want %d", tt.method, tt.path, rec.Code, tt.status)
		}
		if tt.status < 300 && rec.Body.String() != tt.want {
			t.Errorf("%s %s: body %q, want %q", tt.method, tt.path, rec.Body.String(), tt.want)
		}
	}
}

func TestValueLimit(t *testing.T) {
	h := NewServer(NewStore())
	if rec := do(t, h, "PUT", "/kv/big", make([]byte, maxValueSize)); rec.Code != 201 {
		t.Fatalf("1 MiB value: status %d", rec.Code)
	}
	if rec := do(t, h, "PUT", "/kv/big", make([]byte, maxValueSize+1)); rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized value: status %d", rec.Code)
	}
}

func TestConcurrentPuts(t *testing.T) {
	srv := httptest.NewServer(NewServer(NewStore()))
	defer srv.Close()
	var wg sync.WaitGroup
	for i := range 64 {
		wg.Go(func() {
			key := "k" + strings.Repeat("x", i)
			req, _ := http.NewRequest("PUT", srv.URL+"/kv/"+key, strings.NewReader(key))
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Error(err)
				return
			}
			resp.Body.Close()
			if resp.StatusCode != 201 {
				t.Errorf("%s: status %d", key, resp.StatusCode)
			}
		})
	}
	wg.Wait()
}
