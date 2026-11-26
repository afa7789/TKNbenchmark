package httpapi

import (
	"net/http"
	"testing"
)

// seedListNotes creates three notes through the API.
func seedListNotes(t *testing.T, url string) {
	t.Helper()
	for _, body := range []string{
		`{"title":"Hello world","tags":["greet"]}`,
		`{"title":"shopping","body":"say HELLO","tags":["misc"]}`,
		`{"title":"other","tags":["misc"]}`,
	} {
		if status, resp := do(t, http.MethodPost, url+"/notes", body); status != http.StatusCreated {
			t.Fatalf("seed %s = %d %s", body, status, resp)
		}
	}
}

func TestListEmpty(t *testing.T) {
	url := newTestServer(t)
	status, body := do(t, http.MethodGet, url+"/notes", "")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	assertJSON(t, body, `{"notes":[]}`)
}

func TestListQuery(t *testing.T) {
	url := newTestServer(t)
	seedListNotes(t, url)

	n1 := `{"id":1,"title":"Hello world","body":"","tags":["greet"]}`
	n2 := `{"id":2,"title":"shopping","body":"say HELLO","tags":["misc"]}`
	n3 := `{"id":3,"title":"other","body":"","tags":["misc"]}`
	tests := []struct {
		query, want string
	}{
		{"", `[` + n1 + `,` + n2 + `,` + n3 + `]`},
		{"?tag=misc", `[` + n2 + `,` + n3 + `]`},
		{"?tag=Misc", `[]`},
		{"?tag=", `[]`},
		{"?q=hello", `[` + n1 + `,` + n2 + `]`},
		{"?q=", `[` + n1 + `,` + n2 + `,` + n3 + `]`},
		{"?q=hello%20W", `[` + n1 + `]`},
		{"?q=hello&tag=misc", `[` + n2 + `]`},
		{"?after=1", `[` + n2 + `,` + n3 + `]`},
		{"?after=0", `[` + n1 + `,` + n2 + `,` + n3 + `]`},
		{"?after=-5", `[` + n1 + `,` + n2 + `,` + n3 + `]`},
		{"?after=99999999999999999999", `[]`},
		{"?limit=1", `[` + n1 + `]`},
		{"?limit=100", `[` + n1 + `,` + n2 + `,` + n3 + `]`},
		{"?after=1&limit=1", `[` + n2 + `]`},
		{"?tag=misc&q=o&after=2&limit=5", `[` + n3 + `]`},
		{"?unknown=1", `[` + n1 + `,` + n2 + `,` + n3 + `]`},
	}
	for _, tt := range tests {
		status, body := do(t, http.MethodGet, url+"/notes"+tt.query, "")
		if status != http.StatusOK {
			t.Errorf("GET /notes%s = %d, want 200 (%s)", tt.query, status, body)
			continue
		}
		assertJSON(t, body, `{"notes":`+tt.want+`}`)
	}
}

func TestListInvalidParams(t *testing.T) {
	url := newTestServer(t)
	for _, query := range []string{
		"?limit=0", "?limit=101", "?limit=-1", "?limit=", "?limit=abc", "?limit=1.5", "?limit=99999999999999999999",
		"?after=", "?after=abc", "?after=1.5", "?after=1e3",
	} {
		status, body := do(t, http.MethodGet, url+"/notes"+query, "")
		if status != http.StatusBadRequest {
			t.Errorf("GET /notes%s = %d, want 400", query, status)
			continue
		}
		assertError(t, body)
	}
}
