package store

import (
	"reflect"
	"testing"
)

func TestStatsEmpty(t *testing.T) {
	s, _ := openTest(t)
	st, err := s.Stats(t.Context())
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}
	if want := (Stats{Notes: 0, Tags: []TagCount{}}); !reflect.DeepEqual(st, want) {
		t.Errorf("Stats = %+v, want %+v", st, want)
	}
	counts, err := s.TagCounts(t.Context())
	if err != nil {
		t.Fatalf("TagCounts: %v", err)
	}
	if counts == nil || len(counts) != 0 {
		t.Errorf("TagCounts = %#v, want an empty non-nil slice", counts)
	}
}

func TestStatsCountsAndOrder(t *testing.T) {
	s, _ := openTest(t)
	ctx := t.Context()
	mustCreate(t, s, "a", "b", "z")
	mustCreate(t, s, "b", "a", "z")
	gone := mustCreate(t, s, "c", "a", "gone", "z")
	mustCreate(t, s, "d")
	mustCreate(t, s, "e", "c")

	// Tags of a deleted note no longer count.
	if _, err := s.db.ExecContext(ctx, `DELETE FROM notes WHERE id = ?`, gone.ID); err != nil {
		t.Fatalf("delete note: %v", err)
	}

	want := Stats{
		Notes: 4,
		Tags:  []TagCount{{"z", 2}, {"a", 1}, {"b", 1}, {"c", 1}},
	}
	st, err := s.Stats(ctx)
	if err != nil {
		t.Fatalf("Stats: %v", err)
	}
	if !reflect.DeepEqual(st, want) {
		t.Errorf("Stats = %+v, want %+v", st, want)
	}
	counts, err := s.TagCounts(ctx)
	if err != nil {
		t.Fatalf("TagCounts: %v", err)
	}
	if !reflect.DeepEqual(counts, want.Tags) {
		t.Errorf("TagCounts = %+v, want %+v", counts, want.Tags)
	}
}
