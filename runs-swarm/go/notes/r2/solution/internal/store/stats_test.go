package store

import (
	"context"
	"reflect"
	"testing"

	"notes/internal/note"
)

func TestStatsAndTagCountsEmpty(t *testing.T) {
	s, _ := openTestStore(t)
	ctx := context.Background()

	st, err := s.Stats(ctx)
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}
	if st.Notes != 0 || st.Tags == nil || len(st.Tags) != 0 {
		t.Errorf("Stats = %#v, want 0 notes and an empty non-nil map", st)
	}

	counts, err := s.TagCounts(ctx)
	if err != nil {
		t.Fatalf("TagCounts: %v", err)
	}
	if counts == nil || len(counts) != 0 {
		t.Errorf("TagCounts = %#v, want an empty non-nil slice", counts)
	}
}

func TestStatsAndTagCounts(t *testing.T) {
	s, _ := openTestStore(t)
	ctx := context.Background()

	mustCreate(t, s, note.Input{Title: "a", Tags: []string{"b", "z"}})
	mustCreate(t, s, note.Input{Title: "b", Tags: []string{"a", "z"}})
	mustCreate(t, s, note.Input{Title: "c", Tags: []string{"c", "z"}})
	mustCreate(t, s, note.Input{Title: "d", Tags: []string{"b"}})
	mustCreate(t, s, note.Input{Title: "e"})
	// Deleting a note removes its tags from the counts.
	gone := mustCreate(t, s, note.Input{Title: "f", Tags: []string{"a", "gone"}})
	if _, err := s.db.ExecContext(ctx, `DELETE FROM notes WHERE id = ?`, gone.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}

	st, err := s.Stats(ctx)
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}
	want := Stats{Notes: 5, Tags: map[string]int64{"a": 1, "b": 2, "c": 1, "z": 3}}
	if !reflect.DeepEqual(st, want) {
		t.Errorf("Stats = %#v, want %#v", st, want)
	}

	counts, err := s.TagCounts(ctx)
	if err != nil {
		t.Fatalf("TagCounts: %v", err)
	}
	wantCounts := []TagCount{{"z", 3}, {"b", 2}, {"a", 1}, {"c", 1}}
	if !reflect.DeepEqual(counts, wantCounts) {
		t.Errorf("TagCounts = %#v, want %#v", counts, wantCounts)
	}
}
