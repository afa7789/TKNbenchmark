package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func do(t *testing.T, h http.Handler, method, uri, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, uri, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestCRUD(t *testing.T) {
	h := NewHandler(NewStore())
	steps := []struct {
		method, uri, body string
		status            int
		want              string
	}{
		{"PUT", "/kv/a", "hello", 201, ""},
		{"GET", "/kv/a", "", 200, "hello"},
		{"PUT", "/kv/a", "world", 200, ""},
		{"GET", "/kv/a", "", 200, "world"},
		{"DELETE", "/kv/a", "", 204, ""},
		{"GET", "/kv/a", "", 404, ""},
		{"DELETE", "/kv/a", "", 404, ""},
	}
	for _, s := range steps {
		rec := do(t, h, s.method, s.uri, s.body)
		if rec.Code != s.status {
			t.Errorf("%s %s: status %d, want %d", s.method, s.uri, rec.Code, s.status)
		}
		if got := rec.Body.String(); got != s.want {
			t.Errorf("%s %s: body %q, want %q", s.method, s.uri, got, s.want)
		}
	}
}

func TestListing(t *testing.T) {
	h := NewHandler(NewStore())
	for _, k := range []string{"b", "a", "c"} {
		do(t, h, "PUT", "/kv/"+k, k)
	}
	rec := do(t, h, "GET", "/kv", "")
	if rec.Code != 200 {
		t.Fatalf("status %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("content-type %q", ct)
	}
	if got := rec.Body.String(); got != `["a","b","c"]` {
		t.Errorf("body %s", got)
	}
	empty := do(t, NewHandler(NewStore()), "GET", "/kv", "")
	if got := empty.Body.String(); got != "[]" {
		t.Errorf("empty listing %s", got)
	}
}

func TestErrors(t *testing.T) {
	h := NewHandler(NewStore())
	cases := []struct {
		method, uri string
		status      int
	}{
		{"GET", "/kv/", 400},
		{"GET", "/kv/a/b", 400},
		{"GET", "/kv/bad.key", 400},
		{"GET", "/kv/a%2Fb", 400},
		{"GET", "/kv/" + strings.Repeat("a", 65), 400},
		{"GET", "/kv/" + strings.Repeat("a", 64), 404},
		{"GET", "/", 404},
		{"GET", "/nope", 404},
		{"GET", "/health/", 404},
		{"GET", "/kvx", 404},
		{"POST", "/health", 405},
		{"PUT", "/kv", 405},
		{"PATCH", "/kv/a", 405},
	}
	for _, c := range cases {
		if rec := do(t, h, c.method, c.uri, ""); rec.Code != c.status {
			t.Errorf("%s %s: status %d, want %d", c.method, c.uri, rec.Code, c.status)
		}
	}
}
