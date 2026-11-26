package store

import (
	"context"
	"path/filepath"
	"slices"
	"testing"
)

func TestList(t *testing.T) {
	ctx := context.Background()
	s := openTest(t, filepath.Join(t.TempDir(), "notes.db"))
	for _, in := range []NoteInput{
		{Title: "Hello world", Tags: []string{"greet"}},
		{Title: "other", Body: "say HELLO", Tags: []string{"greet", "misc"}},
		{Title: "100%_done", Body: "Ünïcode"},
		{Title: "plain"},
	} {
		if _, err := s.Create(ctx, in); err != nil {
			t.Fatal(err)
		}
	}

	tests := []struct {
		name string
		f    ListFilter
		want []int64
	}{
		{"all", ListFilter{Limit: 100}, []int64{1, 2, 3, 4}},
		{"tag", ListFilter{Tag: "misc", Limit: 100}, []int64{2}},
		{"unknown tag", ListFilter{Tag: "nope", Limit: 100}, []int64{}},
		{"q ignores ascii case", ListFilter{Query: "hElLo", Limit: 100}, []int64{1, 2}},
		{"q is literal", ListFilter{Query: "%_", Limit: 100}, []int64{3}},
		{"q underscore", ListFilter{Query: "_", Limit: 100}, []int64{3}},
		{"q non-ascii case kept", ListFilter{Query: "ünï", Limit: 100}, []int64{}},
		{"q non-ascii exact", ListFilter{Query: "Ünï", Limit: 100}, []int64{3}},
		{"q and tag", ListFilter{Query: "hello", Tag: "misc", Limit: 100}, []int64{2}},
		{"after", ListFilter{After: 2, Limit: 100}, []int64{3, 4}},
		{"negative after", ListFilter{After: -5, Limit: 100}, []int64{1, 2, 3, 4}},
		{"limit", ListFilter{Limit: 2}, []int64{1, 2}},
		{"after and limit", ListFilter{After: 1, Limit: 2}, []int64{2, 3}},
		{"combined", ListFilter{Tag: "greet", After: 1, Limit: 1}, []int64{2}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			notes, err := s.List(ctx, tt.f)
			if err != nil {
				t.Fatal(err)
			}
			if notes == nil {
				t.Fatal("nil result")
			}
			ids := make([]int64, 0, len(notes))
			for _, n := range notes {
				ids = append(ids, n.ID)
				if n.Tags == nil {
					t.Errorf("note %d has nil tags", n.ID)
				}
			}
			if !slices.Equal(ids, tt.want) {
				t.Fatalf("ids = %v, want %v", ids, tt.want)
			}
		})
	}

	notes, err := s.List(ctx, ListFilter{Tag: "misc", Limit: 100})
	if err != nil {
		t.Fatal(err)
	}
	if got := notes[0]; got.Title != "other" || got.Body != "say HELLO" || !slices.Equal(got.Tags, []string{"greet", "misc"}) {
		t.Fatalf("note = %+v", got)
	}
}
