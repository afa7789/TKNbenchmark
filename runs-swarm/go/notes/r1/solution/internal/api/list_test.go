package api

import (
	"net/url"
	"testing"

	"notes/internal/store"
)

func TestParseListFilter(t *testing.T) {
	tests := []struct {
		query string
		want  store.ListFilter
	}{
		{"", store.ListFilter{Limit: 100}},
		{"tag=a-1&q=Hi%20there&after=7&limit=5", store.ListFilter{Tag: "a-1", Query: "Hi there", After: 7, Limit: 5}},
		{"after=-3&limit=100", store.ListFilter{After: -3, Limit: 100}},
		{"limit=1", store.ListFilter{Limit: 1}},
	}
	for _, tt := range tests {
		q, err := url.ParseQuery(tt.query)
		if err != nil {
			t.Fatal(err)
		}
		got, err := parseListFilter(q)
		if err != nil {
			t.Errorf("%q: %v", tt.query, err)
			continue
		}
		if got != tt.want {
			t.Errorf("%q: got %+v, want %+v", tt.query, got, tt.want)
		}
	}
}

func TestParseListFilterErrors(t *testing.T) {
	for _, query := range []string{
		"limit=0", "limit=101", "limit=-1", "limit=", "limit=abc", "limit=1.5", "limit=99999999999999999999",
		"after=", "after=x", "after=1.5", "after=99999999999999999999",
	} {
		q, err := url.ParseQuery(query)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := parseListFilter(q); err == nil {
			t.Errorf("%q: no error", query)
		} else if _, ok := err.(errBadRequest); !ok {
			t.Errorf("%q: error %T is not errBadRequest", query, err)
		}
	}
}
