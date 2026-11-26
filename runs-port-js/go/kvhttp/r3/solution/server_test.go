package main

import (
	"bytes"
	"encoding/json"
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
	h := NewServer(NewStore())
	steps := []struct {
		method, target, body string
		status               int
		want                 string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/kv/bad.key", "", 400, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/%41", "", 400, ""},
		{"GET", "/kv/" + strings.Repeat("k", 65), "", 400, ""},
		{"PUT", "/kv/" + strings.Repeat("k", 64), "x", 201, ""},
		{"PUT", "/kv/a", "hello", 201, ""},
		{"GET", "/kv/a", "", 200, "hello"},
		{"PUT", "/kv/a", "", 200, ""},
		{"GET", "/kv/a", "", 200, ""},
		{"PATCH", "/kv/a", "", 405, ""},
		{"POST", "/kv", "", 405, ""},
		{"DELETE", "/kv/a", "", 204, ""},
		{"DELETE", "/kv/a", "", 404, ""},
		{"GET", "/kv/a", "", 404, ""},
	}
	for _, s := range steps {
		rec := do(t, h, s.method, s.target, []byte(s.body))
		if rec.Code != s.status {
			t.Fatalf("%s %s: status %d, want %d", s.method, s.target, rec.Code, s.status)
		}
		if s.want != "" && rec.Body.String() != s.want {
			t.Fatalf("%s %s: body %q, want %q", s.method, s.target, rec.Body.String(), s.want)
		}
	}
}

func TestList(t *testing.T) {
	h := NewServer(NewStore())
	rec := do(t, h, "GET", "/kv", nil)
	if rec.Body.String() != "[]" {
		t.Fatalf("empty list = %q", rec.Body.String())
	}
	for _, k := range []string{"b", "_", "A", "a", "-"} {
		do(t, h, "PUT", "/kv/"+k, []byte("v"))
	}
	rec = do(t, h, "GET", "/kv", nil)
	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("content-type %q", ct)
	}
	var keys []string
	if err := json.Unmarshal(rec.Body.Bytes(), &keys); err != nil {
		t.Fatal(err)
	}
	want := []string{"-", "A", "_", "a", "b"}
	if strings.Join(keys, ",") != strings.Join(want, ",") {
		t.Fatalf("keys %v, want %v", keys, want)
	}
}

func TestValueLimit(t *testing.T) {
	h := NewServer(NewStore())
	big := bytes.Repeat([]byte{0xff}, MaxValueBytes)
	if rec := do(t, h, "PUT", "/kv/big", big); rec.Code != 201 {
		t.Fatalf("1 MiB value: status %d", rec.Code)
	}
	if rec := do(t, h, "GET", "/kv/big", nil); !bytes.Equal(rec.Body.Bytes(), big) {
		t.Fatal("1 MiB value not returned intact")
	}
	if rec := do(t, h, "PUT", "/kv/big", append(big, 0)); rec.Code != 413 {
		t.Fatalf("oversized value: status %d", rec.Code)
	}
}
