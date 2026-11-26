package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"notes/internal/store"
)

func newTestServer(t *testing.T, dbPath string) *httptest.Server {
	t.Helper()
	st, err := store.Open(context.Background(), dbPath)
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(New(st, slog.New(slog.DiscardHandler)))
	t.Cleanup(func() {
		ts.Close()
		st.Close()
	})
	return ts
}

func do(t *testing.T, ts *httptest.Server, method, path, body string) (int, string) {
	t.Helper()
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, ts.URL+path, rd)
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

func TestAPI(t *testing.T) {
	ts := newTestServer(t, filepath.Join(t.TempDir(), "notes.db"))

	steps := []struct {
		method, path, body string
		status             int
		want               string // exact JSON, or "" to skip
	}{
		{"GET", "/health", "", 200, "ok"},
		{"POST", "/notes", `{"title":"  Hello World ","tags":["b","a","b"]}`, 201, `{"id":1,"title":"Hello World","body":"","tags":["a","b"]}`},
		{"POST", "/notes", `{"title":"second","body":"50% off_now"}`, 201, `{"id":2,"title":"second","body":"50% off_now","tags":[]}`},
		{"POST", "/notes", `{"title":"third","body":"x","tags":["a"]}`, 201, ""},
		{"GET", "/notes?q=hello", "", 200, `{"notes":[{"id":1,"title":"Hello World","body":"","tags":["a","b"]}]}`},
		{"GET", "/notes?q=%25", "", 200, `{"notes":[{"id":2,"title":"second","body":"50% off_now","tags":[]}]}`},
		{"GET", "/notes?q=f_n", "", 200, `{"notes":[{"id":2,"title":"second","body":"50% off_now","tags":[]}]}`},
		{"GET", "/notes?q=f_x", "", 200, `{"notes":[]}`},
		{"GET", "/notes?tag=a&after=1", "", 200, `{"notes":[{"id":3,"title":"third","body":"x","tags":["a"]}]}`},
		{"GET", "/notes?limit=101", "", 400, ""},
		{"GET", "/notes?limit=abc", "", 400, ""},
		{"GET", "/notes?after=", "", 400, ""},
		{"GET", "/notes?after=1.5", "", 400, ""},
		{"GET", "/tags", "", 200, `{"tags":[{"tag":"a","count":2},{"tag":"b","count":1}]}`},
		{"DELETE", "/notes/1", "", 204, ""},
		{"GET", "/stats", "", 200, `{"notes":2,"tags":{"a":1}}`},
		{"DELETE", "/notes", "", 405, ""},
		{"PATCH", "/notes/1", "", 405, ""},
		{"GET", "/notes/", "", 404, ""},
		{"GET", "/notes/-1", "", 404, ""},
		{"GET", "/notes/99999999999999999999", "", 404, ""},
		{"POST", "/notes", `null`, 400, ""},
		{"POST", "/notes", `{"title":"a"} {}`, 400, ""},
		{"POST", "/notes", `{"title":null}`, 400, ""},
		{"POST", "/notes", `{"title":5}`, 400, ""},
		{"POST", "/notes", `{"title":"a","body":null}`, 400, ""},
		{"POST", "/notes", `{"title":"a","tags":"x"}`, 400, ""},
		{"POST", "/notes", `{"title":"a","tags":[1]}`, 400, ""},
		{"POST", "/notes", `{"title":"a","tags":[""]}`, 400, ""},
		{"POST", "/notes", `{"title":"a","tags":["` + strings.Repeat("x", 33) + `"]}`, 400, ""},
		{"POST", "/notes", `{"title":"` + strings.Repeat("é", 201) + `"}`, 400, ""},
		{"POST", "/notes", `{"title":"` + strings.Repeat("é", 200) + `"}`, 201, ""},
		{"PUT", "/notes/2", `{"title":"new"}`, 200, `{"id":2,"title":"new","body":"","tags":[]}`},
		{"PUT", "/notes/1", `{"title":"gone"}`, 404, ""},
		{"PUT", "/notes/2", `{"title":""}`, 400, ""},
	}
	for _, s := range steps {
		status, body := do(t, ts, s.method, s.path, s.body)
		if status != s.status {
			t.Errorf("%s %s %s: status %d, want %d (body %s)", s.method, s.path, s.body, status, s.status, body)
			continue
		}
		if s.want != "" && body != s.want {
			t.Errorf("%s %s: body %s, want %s", s.method, s.path, body, s.want)
		}
	}
}

func TestPersistenceAndIDsNotReused(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "notes.db")
	ts := newTestServer(t, dbPath)
	do(t, ts, "POST", "/notes", `{"title":"a"}`)
	do(t, ts, "POST", "/notes", `{"title":"b"}`)
	do(t, ts, "DELETE", "/notes/2", "")

	ts2 := newTestServer(t, dbPath)
	status, body := do(t, ts2, "POST", "/notes", `{"title":"c"}`)
	if status != 201 || body != `{"id":3,"title":"c","body":"","tags":[]}` {
		t.Fatalf("got %d %s", status, body)
	}
}

func TestConcurrentCreates(t *testing.T) {
	ts := newTestServer(t, filepath.Join(t.TempDir(), "notes.db"))
	const n = 50
	var wg sync.WaitGroup
	for i := range n {
		wg.Go(func() {
			status, body := do(t, ts, "POST", "/notes", fmt.Sprintf(`{"title":"n%d","tags":["t"]}`, i))
			if status != 201 {
				t.Errorf("status %d: %s", status, body)
			}
		})
	}
	wg.Wait()
	_, body := do(t, ts, "GET", "/stats", "")
	var got struct {
		Notes int            `json:"notes"`
		Tags  map[string]int `json:"tags"`
	}
	if err := json.Unmarshal([]byte(body), &got); err != nil {
		t.Fatal(err)
	}
	if got.Notes != n || got.Tags["t"] != n {
		t.Fatalf("stats %s", body)
	}
}
