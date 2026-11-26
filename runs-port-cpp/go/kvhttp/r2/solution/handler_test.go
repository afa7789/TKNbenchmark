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

	big := bytes.Repeat([]byte{0xff, 0x00, 'x'}, maxValueSize/3+1)[:maxValueSize]
	tests := []struct {
		method, path string
		body         []byte
		status       int
		want         string
	}{
		{"GET", "/health", nil, 200, "ok"},
		{"POST", "/health", nil, 405, ""},
		{"GET", "/kv", nil, 200, "[]"},
		{"PUT", "/kv/b", []byte("2"), 201, ""},
		{"PUT", "/kv/A-_9", []byte("1"), 201, ""},
		{"PUT", "/kv/b", []byte("3"), 200, ""},
		{"GET", "/kv/b", nil, 200, "3"},
		{"GET", "/kv", nil, 200, `["A-_9","b"]`},
		{"PUT", "/kv/big", big, 201, ""},
		{"GET", "/kv/big", nil, 200, string(big)},
		{"PUT", "/kv/huge", append(big, 1), 413, ""},
		{"PUT", "/kv/empty", []byte{}, 201, ""},
		{"GET", "/kv/empty", nil, 200, ""},
		{"DELETE", "/kv/b", nil, 204, ""},
		{"DELETE", "/kv/b", nil, 404, ""},
		{"GET", "/kv/b", nil, 404, ""},
		{"PATCH", "/kv/a", nil, 405, ""},
		{"POST", "/kv", nil, 405, ""},
		{"GET", "/kv/", nil, 400, ""},
		{"GET", "/kv/a/b", nil, 400, ""},
		{"GET", "/kv/bad.key", nil, 400, ""},
		{"GET", "/kv/%41", nil, 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 64), nil, 404, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), nil, 400, ""},
		{"GET", "/nope", nil, 404, ""},
		{"GET", "/", nil, 404, ""},
		{"GET", "/kvx", nil, 404, ""},
	}
	for _, tt := range tests {
		status, hdr, body := do(t, srv, tt.method, tt.path, tt.body)
		if status != tt.status {
			t.Errorf("%s %s: status %d, want %d", tt.method, tt.path, status, tt.status)
			continue
		}
		if tt.want != "" && string(body) != tt.want {
			t.Errorf("%s %s: body %.40q, want %.40q", tt.method, tt.path, body, tt.want)
		}
		if tt.path == "/kv" && status == 200 && hdr.Get("Content-Type") != "application/json" {
			t.Errorf("GET /kv: content-type %q", hdr.Get("Content-Type"))
		}
	}
}

func TestConcurrentPuts(t *testing.T) {
	store := NewStore()
	srv := httptest.NewServer(NewHandler(store))
	defer srv.Close()

	var wg sync.WaitGroup
	for i := range 64 {
		wg.Go(func() {
			key := "k" + strings.Repeat("x", i%10) + string(rune('a'+i%26))
			req, _ := http.NewRequest("PUT", srv.URL+"/kv/"+key, strings.NewReader(key))
			resp, err := srv.Client().Do(req)
			if err != nil {
				t.Error(err)
				return
			}
			resp.Body.Close()
		})
	}
	wg.Wait()
	if n := len(store.Keys()); n == 0 {
		t.Fatal("no keys stored")
	}
}
