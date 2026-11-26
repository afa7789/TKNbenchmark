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

	"kvhttp/internal/kv"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(newHandler(kv.NewStore()))
	t.Cleanup(srv.Close)
	return srv
}

func do(t *testing.T, srv *httptest.Server, method, path string, body []byte) (int, http.Header, []byte) {
	t.Helper()
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, srv.URL, r)
	if err != nil {
		t.Fatal(err)
	}
	req.URL.Opaque = path // send the path verbatim
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, resp.Header, data
}

func TestRoutes(t *testing.T) {
	srv := newTestServer(t)
	big := bytes.Repeat([]byte{0xff}, maxBodyBytes)

	steps := []struct {
		method, path string
		body         []byte
		status       int
		want         string
	}{
		{"GET", "/health", nil, 200, "ok"},
		{"POST", "/health", nil, 405, ""},
		{"GET", "/kv", nil, 200, "[]"},
		{"POST", "/kv", nil, 405, ""},
		{"PUT", "/kv/b", []byte("2"), 201, ""},
		{"PUT", "/kv/a", []byte{}, 201, ""},
		{"PUT", "/kv/a", []byte("1"), 200, ""},
		{"GET", "/kv/a", nil, 200, "1"},
		{"GET", "/kv", nil, 200, `["a","b"]`},
		{"PATCH", "/kv/a", nil, 405, ""},
		{"DELETE", "/kv/a", nil, 204, ""},
		{"DELETE", "/kv/a", nil, 404, ""},
		{"GET", "/kv/a", nil, 404, ""},
		{"GET", "/kv/", nil, 400, ""},
		{"GET", "/kv/a/b", nil, 400, ""},
		{"GET", "/kv/bad.key", nil, 400, ""},
		{"GET", "/kv/%41", nil, 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), nil, 400, ""},
		{"PATCH", "/kv/bad.key", nil, 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), nil, 404, ""},
		{"GET", "/nope", nil, 404, ""},
		{"GET", "/kv/../health", nil, 400, ""},
		{"PUT", "/kv/big", big, 201, ""},
		{"GET", "/kv/big", nil, 200, string(big)},
		{"PUT", "/kv/huge", append(big, 0), 413, ""},
	}
	for _, s := range steps {
		status, _, body := do(t, srv, s.method, s.path, s.body)
		if status != s.status || string(body) != s.want {
			t.Errorf("%s %s = %d (%d bytes), want %d (%d bytes)", s.method, s.path, status, len(body), s.status, len(s.want))
		}
	}
}

func TestConcurrent(t *testing.T) {
	srv := newTestServer(t)
	var wg sync.WaitGroup
	for i := range 128 {
		wg.Go(func() {
			key := fmt.Sprintf("/kv/k%d", i)
			val := []byte(strings.Repeat("v", i*1000))
			if status, _, _ := do(t, srv, "PUT", key, val); status != 201 {
				t.Errorf("PUT %s = %d", key, status)
			}
			if status, _, body := do(t, srv, "GET", key, nil); status != 200 || !bytes.Equal(body, val) {
				t.Errorf("GET %s = %d", key, status)
			}
		})
	}
	wg.Wait()
}
