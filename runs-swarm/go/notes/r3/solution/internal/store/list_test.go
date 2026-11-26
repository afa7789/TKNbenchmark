package store

import (
	"reflect"
	"testing"

	"notes/internal/note"
)

func ptr[T any](v T) *T { return &v }

func ids(notes []note.Note) []int64 {
	out := make([]int64, 0, len(notes))
	for _, n := range notes {
		out = append(out, n.ID)
	}
	return out
}

func TestListEmpty(t *testing.T) {
	s, _ := openTest(t)
	notes, err := s.List(t.Context(), Filter{})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if notes == nil || len(notes) != 0 {
		t.Errorf("List on empty store = %#v, want empty non-nil slice", notes)
	}
}

func TestListFilters(t *testing.T) {
	s, _ := openTest(t)
	ctx := t.Context()
	mustCreate(t, s, "Hello World", "greet")     // 1
	mustCreate(t, s, "shopping", "misc", "todo") // 2
	if _, err := s.Create(ctx, note.Input{Title: "other", Body: "say HELLO", Tags: []string{"misc"}}); err != nil {
		t.Fatal(err) // 3
	}
	mustCreate(t, s, "100% sure_thing") // 4
	mustCreate(t, s, "Ünïcode")         // 5

	tests := []struct {
		name string
		f    Filter
		want []int64
	}{
		{"all", Filter{}, []int64{1, 2, 3, 4, 5}},
		{"tag", Filter{Tag: ptr("misc")}, []int64{2, 3}},
		{"unknown tag", Filter{Tag: ptr("nope")}, []int64{}},
		{"empty tag", Filter{Tag: ptr("")}, []int64{}},
		{"q title or body, any ASCII case", Filter{Query: ptr("hElLo")}, []int64{1, 3}},
		{"q empty", Filter{Query: ptr("")}, []int64{1, 2, 3, 4, 5}},
		{"q percent is literal", Filter{Query: ptr("%")}, []int64{4}},
		{"q underscore is literal", Filter{Query: ptr("e_t")}, []int64{4}},
		{"q non-ASCII case is significant", Filter{Query: ptr("ünï")}, []int64{}},
		{"q non-ASCII exact", Filter{Query: ptr("Ünï")}, []int64{5}},
		{"q and tag", Filter{Query: ptr("hello"), Tag: ptr("misc")}, []int64{3}},
		{"after", Filter{After: 3}, []int64{4, 5}},
		{"after negative", Filter{After: -10}, []int64{1, 2, 3, 4, 5}},
		{"limit", Filter{Limit: 2}, []int64{1, 2}},
		{"after and limit", Filter{After: 1, Limit: 2}, []int64{2, 3}},
		{"everything", Filter{Tag: ptr("misc"), Query: ptr("o"), After: 2, Limit: 1}, []int64{3}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			notes, err := s.List(ctx, tt.f)
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			if got := ids(notes); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("ids = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestListReturnsFullNotes(t *testing.T) {
	s, _ := openTest(t)
	ctx := t.Context()
	want, err := s.Create(ctx, note.Input{Title: "t", Body: "b", Tags: []string{"a", "z"}})
	if err != nil {
		t.Fatal(err)
	}
	bare := mustCreate(t, s, "bare")
	notes, err := s.List(ctx, Filter{})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if !reflect.DeepEqual(notes, []note.Note{want, bare}) {
		t.Errorf("List = %+v, want %+v", notes, []note.Note{want, bare})
	}
}

func TestListLimitCap(t *testing.T) {
	s, _ := openTest(t)
	for range MaxListLimit + 5 {
		mustCreate(t, s, "n")
	}
	for _, limit := range []int{0, MaxListLimit + 1} {
		notes, err := s.List(t.Context(), Filter{Limit: limit})
		if err != nil {
			t.Fatalf("List: %v", err)
		}
		if len(notes) != MaxListLimit {
			t.Errorf("Limit %d: got %d notes, want %d", limit, len(notes), MaxListLimit)
		}
	}
}
