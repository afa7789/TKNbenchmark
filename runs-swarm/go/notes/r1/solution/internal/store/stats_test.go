package store

import (
	"context"
	"path/filepath"
	"reflect"
	"testing"
)

func TestStatsEmpty(t *testing.T) {
	s := openTest(t, filepath.Join(t.TempDir(), "notes.db"))
	got, err := s.Stats(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	want := Stats{Notes: 0, Tags: []TagCount{}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Stats() = %+v, want %+v", got, want)
	}
}

func TestStatsOrderAndDelete(t *testing.T) {
	ctx := context.Background()
	s := openTest(t, filepath.Join(t.TempDir(), "notes.db"))
	for _, tags := range [][]string{
		{"b", "c"},
		{"a", "c"},
		{"c", "z"},
		{"d"},
		nil,
	} {
		if _, err := s.Create(ctx, NoteInput{Title: "t", Tags: tags}); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.Stats(ctx)
	if err != nil {
		t.Fatal(err)
	}
	want := Stats{Notes: 5, Tags: []TagCount{
		{"c", 3}, {"a", 1}, {"b", 1}, {"d", 1}, {"z", 1},
	}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Stats() = %+v, want %+v", got, want)
	}

	// Tags of deleted notes no longer count.
	if _, err := s.db.ExecContext(ctx, `DELETE FROM notes WHERE id IN (3, 4)`); err != nil {
		t.Fatal(err)
	}
	got, err = s.Stats(ctx)
	if err != nil {
		t.Fatal(err)
	}
	want = Stats{Notes: 3, Tags: []TagCount{{"c", 2}, {"a", 1}, {"b", 1}}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("after delete Stats() = %+v, want %+v", got, want)
	}
}
