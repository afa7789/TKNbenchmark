package server

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"notes/internal/notes"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	store, err := notes.Open(context.Background(), filepath.Join(t.TempDir(), "notes.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	ts := httptest.NewServer(New(store, slog.New(slog.DiscardHandler)))
	t.Cleanup(ts.Close)
	return ts
}

func do(t *testing.T, ts *httptest.Server, method, path, body string) (int, string) {
	t.Helper()
	req, err := http.NewRequest(method, ts.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	res, err := ts.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	data, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	return res.StatusCode, strings.TrimSpace(string(data))
}

func TestStatusCodes(t *testing.T) {
	ts := newTestServer(t)
	steps := []struct {
		method, path, body string
		status             int
		resp               string
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/health", "", 405, ""},
		{"POST", "/notes", `{"title":"a","tags":["y","x"]}`, 201, `{"id":1,"title":"a","body":"","tags":["x","y"]}`},
		{"POST", "/notes", `{"title":"b","tags":["x"]}`, 201, ""},
		{"POST", "/notes", `{"title":5}`, 400, ""},
		{"DELETE", "/notes", "", 405, ""},
		{"PATCH", "/notes/1", "", 405, ""},
		{"GET", "/notes/1", "", 200, `{"id":1,"title":"a","body":"","tags":["x","y"]}`},
		{"GET", "/notes/-1", "", 404, ""},
		{"GET", "/notes/+1", "", 404, ""},
		{"GET", "/notes/99999999999999999999", "", 404, ""},
		{"GET", "/notes/1/extra", "", 404, ""},
		{"GET", "/notes/", "", 404, ""},
		{"PUT", "/notes/1", `{"title":"z"}`, 200, `{"id":1,"title":"z","body":"","tags":[]}`},
		{"PUT", "/notes/9", `{"title":"z"}`, 404, ""},
		{"PUT", "/notes/1", `{"title":""}`, 400, ""},
		{"GET", "/tags", "", 200, `{"tags":[{"tag":"x","count":1}]}`},
		{"DELETE", "/notes/2", "", 204, ""},
		{"DELETE", "/notes/2", "", 404, ""},
		{"GET", "/stats", "", 200, `{"notes":1,"tags":{}}`},
		{"GET", "/notes?limit=abc", "", 400, ""},
		{"GET", "/notes?limit=", "", 400, ""},
		{"GET", "/notes?after=-5", "", 200, `{"notes":[{"id":1,"title":"z","body":"","tags":[]}]}`},
		{"GET", "/notes?after=1.5", "", 400, ""},
		{"GET", "/missing", "", 404, ""},
	}
	for _, s := range steps {
		status, body := do(t, ts, s.method, s.path, s.body)
		if status != s.status {
			t.Errorf("%s %s: status %d, want %d (body %s)", s.method, s.path, status, s.status, body)
		}
		if s.resp != "" && body != s.resp {
			t.Errorf("%s %s: body %s, want %s", s.method, s.path, body, s.resp)
		}
		if status >= 400 {
			var e struct{ Error string }
			if err := json.Unmarshal([]byte(body), &e); err != nil || e.Error == "" {
				t.Errorf("%s %s: error body %q is not {\"error\": ...}", s.method, s.path, body)
			}
		}
	}
}

func TestConcurrentCreates(t *testing.T) {
	ts := newTestServer(t)
	const n = 50
	var wg sync.WaitGroup
	for range n {
		wg.Go(func() {
			if status, body := do(t, ts, "POST", "/notes", `{"title":"t","tags":["c"]}`); status != 201 {
				t.Errorf("status %d: %s", status, body)
			}
		})
	}
	wg.Wait()
	if _, body := do(t, ts, "GET", "/stats", ""); body != `{"notes":50,"tags":{"c":50}}` {
		t.Fatalf("stats = %s", body)
	}
}
