package store

import (
	"context"
	"math"
	"slices"
	"testing"

	"notes/internal/note"
)

// seedListNotes creates notes 1..5 used by the list tests.
func seedListNotes(t *testing.T, s *Store) {
	t.Helper()
	for _, in := range []note.Input{
		{Title: "Hello world", Tags: []string{"greet"}},
		{Title: "shopping", Body: "buy MILK", Tags: []string{"home", "misc"}},
		{Title: "hello again", Body: "x", Tags: []string{"misc"}},
		{Title: "100% done_ok", Body: ""},
		{Title: "Café", Body: "ÉCLAIR", Tags: []string{"misc"}},
	} {
		mustCreate(t, s, in)
	}
}

func ids(notes []note.Note) []int64 {
	out := []int64{}
	for _, n := range notes {
		out = append(out, n.ID)
	}
	return out
}

func ptr[T any](v T) *T { return &v }

func TestList(t *testing.T) {
	s, _ := openTestStore(t)
	seedListNotes(t, s)

	tests := []struct {
		name string
		f    ListFilter
		want []int64
	}{
		{"all", ListFilter{}, []int64{1, 2, 3, 4, 5}},
		{"tag", ListFilter{Tag: ptr("misc")}, []int64{2, 3, 5}},
		{"unknown tag", ListFilter{Tag: ptr("nope")}, []int64{}},
		{"empty tag", ListFilter{Tag: ptr("")}, []int64{}},
		{"query ignores ascii case", ListFilter{Query: "HELLO"}, []int64{1, 3}},
		{"query matches body", ListFilter{Query: "milk"}, []int64{2}},
		{"query percent is literal", ListFilter{Query: "%"}, []int64{4}},
		{"query underscore is literal", ListFilter{Query: "e_o"}, []int64{4}},
		{"query non-ascii case is significant", ListFilter{Query: "éclair"}, []int64{}},
		{"query non-ascii exact", ListFilter{Query: "Éclair"}, []int64{5}},
		{"after", ListFilter{After: 3}, []int64{4, 5}},
		{"after negative", ListFilter{After: -10}, []int64{1, 2, 3, 4, 5}},
		{"after max", ListFilter{After: math.MaxInt64}, []int64{}},
		{"limit", ListFilter{Limit: 2}, []int64{1, 2}},
		{"combined", ListFilter{Tag: ptr("misc"), Query: "hello", After: 1, Limit: 1}, []int64{3}},
		{"after and limit", ListFilter{After: 2, Limit: 2}, []int64{3, 4}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := s.List(context.Background(), tt.f)
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			if !slices.Equal(ids(got), tt.want) {
				t.Errorf("ids = %v, want %v", ids(got), tt.want)
			}
		})
	}
}

func TestListReturnsFullNotes(t *testing.T) {
	s, _ := openTestStore(t)
	seedListNotes(t, s)
	got, err := s.List(context.Background(), ListFilter{Tag: ptr("home")})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("got %d notes, want 1", len(got))
	}
	want := note.Note{ID: 2, Title: "shopping", Body: "buy MILK", Tags: []string{"home", "misc"}}
	if n := got[0]; n.ID != want.ID || n.Title != want.Title || n.Body != want.Body || !slices.Equal(n.Tags, want.Tags) {
		t.Errorf("got %#v, want %#v", n, want)
	}
}

func TestListDefaultLimit(t *testing.T) {
	s, _ := openTestStore(t)
	for range MaxListLimit + 5 {
		mustCreate(t, s, note.Input{Title: "n"})
	}
	got, err := s.List(context.Background(), ListFilter{})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(got) != MaxListLimit || got[0].ID != 1 {
		t.Errorf("got %d notes starting at %d, want %d starting at 1", len(got), got[0].ID, MaxListLimit)
	}
}
