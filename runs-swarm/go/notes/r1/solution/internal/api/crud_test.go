package api

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"notes/internal/store"
)

func newTestServer(t *testing.T) http.Handler {
	t.Helper()
	st, err := store.Open(context.Background(), filepath.Join(t.TempDir(), "notes.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	return New(st, slog.New(slog.DiscardHandler)).Handler()
}

func do(t *testing.T, h http.Handler, method, path, body string) (int, string) {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, strings.NewReader(body)))
	b, _ := io.ReadAll(rec.Body)
	return rec.Code, string(b)
}

func TestUpdateDeleteHandlers(t *testing.T) {
	h := newTestServer(t)
	if code, _ := do(t, h, "POST", "/notes", `{"title":"a","tags":["x"]}`); code != http.StatusCreated {
		t.Fatalf("create: %d", code)
	}

	for _, tc := range []struct {
		method, path, body string
		want               int
	}{
		{"PUT", "/notes/1", `{"title":" new ","tags":["b","a","b"]}`, http.StatusOK},
		{"PUT", "/notes/1", `{"title":""}`, http.StatusBadRequest},
		{"PUT", "/notes/1", `not json`, http.StatusBadRequest},
		{"PUT", "/notes/9", `{"title":"x"}`, http.StatusNotFound},
		{"PUT", "/notes/0", `{"title":"x"}`, http.StatusNotFound},
		{"PUT", "/notes/abc", `{"title":"x"}`, http.StatusNotFound},
		{"DELETE", "/notes/abc", ``, http.StatusNotFound},
		{"DELETE", "/notes/-1", ``, http.StatusNotFound},
		{"DELETE", "/notes/9", ``, http.StatusNotFound},
		{"DELETE", "/notes", ``, http.StatusMethodNotAllowed},
		{"PATCH", "/notes/1", `{}`, http.StatusMethodNotAllowed},
	} {
		if code, body := do(t, h, tc.method, tc.path, tc.body); code != tc.want {
			t.Errorf("%s %s %s: status %d (%s), want %d", tc.method, tc.path, tc.body, code, body, tc.want)
		}
	}

	if _, body := do(t, h, "GET", "/notes/1", ""); strings.TrimSpace(body) != `{"id":1,"title":"new","body":"","tags":["a","b"]}` {
		t.Errorf("after update: %s", body)
	}

	code, body := do(t, h, "DELETE", "/notes/1", "")
	if code != http.StatusNoContent || body != "" {
		t.Errorf("delete: %d %q", code, body)
	}
	if code, _ := do(t, h, "GET", "/notes/1", ""); code != http.StatusNotFound {
		t.Errorf("get after delete: %d", code)
	}
	if code, _ := do(t, h, "PUT", "/notes/1", `{"title":"x"}`); code != http.StatusNotFound {
		t.Errorf("put after delete: %d", code)
	}
}
