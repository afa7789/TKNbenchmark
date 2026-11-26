package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestUnmatchedRoutesAnswerJSON(t *testing.T) {
	h := newTestServer(t)
	for _, tc := range []struct {
		method, path string
		want         int
		allow        string
	}{
		{"GET", "/nope", http.StatusNotFound, ""},
		{"GET", "/notes/", http.StatusNotFound, ""},
		{"GET", "/notes/1/x", http.StatusNotFound, ""},
		{"DELETE", "/notes", http.StatusMethodNotAllowed, "GET, HEAD, POST"},
		{"POST", "/stats", http.StatusMethodNotAllowed, "GET, HEAD"},
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(tc.method, tc.path, nil))
		if rec.Code != tc.want {
			t.Errorf("%s %s: status %d, want %d", tc.method, tc.path, rec.Code, tc.want)
		}
		if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
			t.Errorf("%s %s: Content-Type %q", tc.method, tc.path, ct)
		}
		if body := rec.Body.String(); !strings.HasPrefix(body, `{"error":`) {
			t.Errorf("%s %s: body %q", tc.method, tc.path, body)
		}
		if got := rec.Header().Get("Allow"); got != tc.allow {
			t.Errorf("%s %s: Allow %q, want %q", tc.method, tc.path, got, tc.allow)
		}
	}
}
