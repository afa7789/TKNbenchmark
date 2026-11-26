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

func do(t *testing.T, srv *httptest.Server, method, path string, body []byte) (int, http.Header, []byte) {
	t.Helper()
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, srv.URL+path, rd)
	if err != nil {
		t.Fatal(err)
	}
	req.Close = true
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, resp.Header, b
}

func TestRoutes(t *testing.T) {
	srv := httptest.NewServer(NewHandler(NewStore()))
	defer srv.Close()

	long := strings.Repeat("a", 64)
	tests := []struct {
		method, path, body string
		status             int
		want               string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"POST", "/kv", "", 405, ""},
		{"PUT", "/kv/b", "2", 201, ""},
		{"PUT", "/kv/a", "1", 201, ""},
		{"PUT", "/kv/a", "11", 200, ""},
		{"GET", "/kv/a", "", 200, "11"},
		{"GET", "/kv", "", 200, `["a","b"]`},
		{"PUT", "/kv/" + long, "", 201, ""},
		{"GET", "/kv/" + long, "", 200, ""},
		{"GET", "/kv/" + long + "a", "", 400, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/a.b", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"PATCH", "/kv/a", "", 405, ""},
		{"PATCH", "/kv/a.b", "", 400, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
		{"GET", "/kvx", "", 404, ""},
		{"GET", "/health/", "", 404, ""},
	}
	for _, tc := range tests {
		var body []byte
		if tc.method == "PUT" {
			body = []byte(tc.body)
		}
		status, _, got := do(t, srv, tc.method, tc.path, body)
		if status != tc.status || string(got) != tc.want {
			t.Errorf("%s %s: got %d %q, want %d %q", tc.method, tc.path, status, got, tc.status, tc.want)
		}
	}
}

func TestLargeValues(t *testing.T) {
	srv := httptest.NewServer(NewHandler(NewStore()))
	defer srv.Close()

	value := make([]byte, MaxValueBytes)
	for i := range value {
		value[i] = byte(i * 7)
	}
	if status, _, _ := do(t, srv, "PUT", "/kv/big", value); status != 201 {
		t.Fatalf("PUT max value: status %d", status)
	}
	status, hdr, got := do(t, srv, "GET", "/kv/big", nil)
	if status != 200 || !bytes.Equal(got, value) || hdr.Get("Content-Length") != fmt.Sprint(MaxValueBytes) {
		t.Fatalf("GET max value: status %d, %d bytes", status, len(got))
	}
	if status, _, _ := do(t, srv, "PUT", "/kv/big2", append(value, 0)); status != 413 {
		t.Fatalf("PUT oversized value: status %d, want 413", status)
	}
}

func TestConcurrent(t *testing.T) {
	srv := httptest.NewServer(NewHandler(NewStore()))
	defer srv.Close()

	var wg sync.WaitGroup
	for i := range 128 {
		wg.Go(func() {
			key := fmt.Sprintf("k%03d", i)
			if status, _, _ := do(t, srv, "PUT", "/kv/"+key, []byte(key)); status != 201 {
				t.Errorf("PUT %s: status %d", key, status)
			}
			if _, _, got := do(t, srv, "GET", "/kv/"+key, nil); string(got) != key {
				t.Errorf("GET %s: %q", key, got)
			}
		})
	}
	wg.Wait()
	_, _, got := do(t, srv, "GET", "/kv", nil)
	if n := strings.Count(string(got), ","); n != 127 {
		t.Errorf("list has %d commas, want 127", n)
	}
}
