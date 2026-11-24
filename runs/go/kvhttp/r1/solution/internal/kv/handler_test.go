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
	long := strings.Repeat("a", 64)
	tests := []struct {
		method, target, body string
		status               int
		want                 string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"GET", "/health/", "", 404, ""},
		{"GET", "/nope", "", 404, ""},
		{"GET", "/", "", 404, ""},
		{"GET", "/kv", "", 200, "[]"},
		{"POST", "/kv", "", 405, ""},
		{"GET", "/kv/", "", 400, ""},
		{"GET", "/kv/a/b", "", 400, ""},
		{"GET", "/kv/a.b", "", 400, ""},
		{"GET", "/kv/a%2Fb", "", 400, ""},
		{"GET", "/kv/" + long + "a", "", 400, ""},
		{"PUT", "/kv/" + long, "v", 201, ""},
		{"PUT", "/kv/" + long, "w", 200, ""},
		{"GET", "/kv/" + long, "", 200, "w"},
		{"PATCH", "/kv/a", "", 405, ""},
		{"PUT", "/kv/empty", "", 201, ""},
		{"GET", "/kv/empty", "", 200, ""},
		{"DELETE", "/kv/empty", "", 204, ""},
		{"DELETE", "/kv/empty", "", 404, ""},
		{"GET", "/kv", "", 200, `["` + long + `"]`},
	}
	for _, tc := range tests {
		rec := do(t, h, tc.method, tc.target, []byte(tc.body))
		if rec.Code != tc.status {
			t.Errorf("%s %s: status %d, want %d", tc.method, tc.target, rec.Code, tc.status)
			continue
		}
		if tc.want != "" && rec.Body.String() != tc.want {
			t.Errorf("%s %s: body %q, want %q", tc.method, tc.target, rec.Body.String(), tc.want)
		}
	}
}

func TestValueSizeLimit(t *testing.T) {
	h := NewHandler(NewStore())
	max := bytes.Repeat([]byte{0xff}, MaxValueSize)
	if rec := do(t, h, "PUT", "/kv/big", max); rec.Code != 201 {
		t.Fatalf("max-size put: status %d", rec.Code)
	}
	if rec := do(t, h, "GET", "/kv/big", nil); !bytes.Equal(rec.Body.Bytes(), max) {
		t.Fatal("max-size value not round-tripped")
	}
	if rec := do(t, h, "PUT", "/kv/big", append(max, 0)); rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversize put: status %d", rec.Code)
	}
}

func TestConcurrent(t *testing.T) {
	srv := httptest.NewServer(NewHandler(NewStore()))
	defer srv.Close()
	var wg sync.WaitGroup
	for i := range 128 {
		wg.Go(func() {
			url := fmt.Sprintf("%s/kv/k%d", srv.URL, i)
			req, _ := http.NewRequest(http.MethodPut, url, strings.NewReader(fmt.Sprint(i)))
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Error(err)
				return
			}
			resp.Body.Close()
			if resp.StatusCode != 201 {
				t.Errorf("put %d: status %d", i, resp.StatusCode)
			}
		})
	}
	wg.Wait()
	resp, err := http.Get(srv.URL + "/kv")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if n := strings.Count(string(body), `"`) / 2; n != 128 {
		t.Fatalf("got %d keys, want 128", n)
	}
}
