package api

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
	srv := httptest.NewServer(New(st, slog.New(slog.DiscardHandler)))
	t.Cleanup(func() {
		srv.Close()
		st.Close()
	})
	return srv
}

func do(t *testing.T, srv *httptest.Server, method, path, body string) (int, string) {
	t.Helper()
	req, err := http.NewRequest(method, srv.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(data)
}

func expect(t *testing.T, srv *httptest.Server, method, path, body string, wantStatus int, wantBody string) {
	t.Helper()
	status, got := do(t, srv, method, path, body)
	if status != wantStatus {
		t.Fatalf("%s %s: status %d, want %d (body %s)", method, path, status, wantStatus, got)
	}
	if wantBody != "" && got != wantBody {
		t.Fatalf("%s %s: body %s, want %s", method, path, got, wantBody)
	}
}

func TestAPI(t *testing.T) {
	srv := newTestServer(t, filepath.Join(t.TempDir(), "notes.db"))

	expect(t, srv, "GET", "/health", "", 200, "ok")
	expect(t, srv, "POST", "/notes", `{"title":"Hello","body":"World","tags":["b","a"]}`, 201, `{"id":1,"title":"Hello","body":"World","tags":["a","b"]}`)
	expect(t, srv, "POST", "/notes", `{"title":"second","body":"hello 100%","tags":["a"]}`, 201, "")
	expect(t, srv, "POST", "/notes", `{"title":"third"}`, 201, "")

	expect(t, srv, "GET", "/notes?q=HELLO", "", 200, `{"notes":[{"id":1,"title":"Hello","body":"World","tags":["a","b"]},{"id":2,"title":"second","body":"hello 100%","tags":["a"]}]}`)
	expect(t, srv, "GET", "/notes?q=%25", "", 200, `{"notes":[{"id":2,"title":"second","body":"hello 100%","tags":["a"]}]}`)
	expect(t, srv, "GET", "/notes?q=_", "", 200, `{"notes":[]}`)
	expect(t, srv, "GET", "/notes?tag=b", "", 200, `{"notes":[{"id":1,"title":"Hello","body":"World","tags":["a","b"]}]}`)
	expect(t, srv, "GET", "/notes?tag=a&after=1&limit=1", "", 200, `{"notes":[{"id":2,"title":"second","body":"hello 100%","tags":["a"]}]}`)
	expect(t, srv, "GET", "/notes?limit=101", "", 400, "")
	expect(t, srv, "GET", "/notes?limit=x", "", 400, "")
	expect(t, srv, "GET", "/notes?after=x", "", 400, "")

	expect(t, srv, "GET", "/tags", "", 200, `{"tags":[{"tag":"a","count":2},{"tag":"b","count":1}]}`)
	expect(t, srv, "DELETE", "/notes/1", "", 204, "")
	expect(t, srv, "GET", "/stats", "", 200, `{"notes":2,"tags":{"a":1}}`)
	expect(t, srv, "PUT", "/notes/2", `{"title":"x"}`, 200, `{"id":2,"title":"x","body":"","tags":[]}`)
	expect(t, srv, "GET", "/stats", "", 200, `{"notes":2,"tags":{}}`)

	expect(t, srv, "DELETE", "/notes", "", 405, "")
	expect(t, srv, "POST", "/notes/2", "", 405, "")
	expect(t, srv, "POST", "/stats", "", 405, "")
	expect(t, srv, "GET", "/notes/2/x", "", 404, "")
	expect(t, srv, "PUT", "/notes/abc", `{"title":"x"}`, 404, "")
}

func TestPersistenceAndIDsNeverReused(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "notes.db")
	srv := newTestServer(t, dbPath)
	expect(t, srv, "POST", "/notes", `{"title":"a"}`, 201, "")
	expect(t, srv, "POST", "/notes", `{"title":"b","tags":["t"]}`, 201, "")
	expect(t, srv, "DELETE", "/notes/2", "", 204, "")
	srv.Close()

	srv2 := newTestServer(t, dbPath)
	expect(t, srv2, "GET", "/notes/1", "", 200, `{"id":1,"title":"a","body":"","tags":[]}`)
	expect(t, srv2, "POST", "/notes", `{"title":"c"}`, 201, `{"id":3,"title":"c","body":"","tags":[]}`)
}

func TestConcurrentCreates(t *testing.T) {
	srv := newTestServer(t, filepath.Join(t.TempDir(), "notes.db"))
	const n = 100
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for i := range n {
		wg.Go(func() {
			status, body := do(t, srv, "POST", "/notes", fmt.Sprintf(`{"title":"n%d","tags":["t"]}`, i))
			if status != 201 {
				errs <- fmt.Errorf("status %d: %s", status, body)
			}
		})
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	_, body := do(t, srv, "GET", "/stats", "")
	var stats struct {
		Notes int            `json:"notes"`
		Tags  map[string]int `json:"tags"`
	}
	if err := json.Unmarshal([]byte(body), &stats); err != nil {
		t.Fatal(err)
	}
	if stats.Notes != n || stats.Tags["t"] != n {
		t.Fatalf("stats = %+v, want %d notes", stats, n)
	}
}
