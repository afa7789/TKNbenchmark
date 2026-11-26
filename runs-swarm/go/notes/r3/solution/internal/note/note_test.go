package note

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

func TestNormalize(t *testing.T) {
	got, err := Input{Title: "  hi  ", Body: "b", Tags: []string{"work", "b-2", "work"}}.Normalize()
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	want := Input{Title: "hi", Body: "b", Tags: []string{"b-2", "work"}}
	if got.Title != want.Title || got.Body != want.Body || !slices.Equal(got.Tags, want.Tags) {
		t.Errorf("Normalize = %+v, want %+v", got, want)
	}
}

func TestNormalizeNilTags(t *testing.T) {
	got, err := Input{Title: "x"}.Normalize()
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if got.Tags == nil || len(got.Tags) != 0 {
		t.Errorf("Tags = %#v, want empty non-nil slice", got.Tags)
	}
}

func TestNormalizeErrors(t *testing.T) {
	tests := []struct {
		name string
		in   Input
	}{
		{"empty title", Input{Title: ""}},
		{"blank title", Input{Title: "   "}},
		{"long title", Input{Title: strings.Repeat("é", MaxTitleLen+1)}},
		{"uppercase tag", Input{Title: "x", Tags: []string{"Bad"}}},
		{"empty tag", Input{Title: "x", Tags: []string{""}}},
		{"long tag", Input{Title: "x", Tags: []string{strings.Repeat("a", MaxTagLen+1)}}},
		{"space in tag", Input{Title: "x", Tags: []string{"a b"}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := tt.in.Normalize()
			var verr *ValidationError
			if !errors.As(err, &verr) {
				t.Fatalf("Normalize error = %v, want *ValidationError", err)
			}
		})
	}
}

func TestNormalizeLimits(t *testing.T) {
	in := Input{Title: strings.Repeat("é", MaxTitleLen), Tags: []string{strings.Repeat("a", MaxTagLen), "0-9"}}
	if _, err := in.Normalize(); err != nil {
		t.Errorf("Normalize at limits: %v", err)
	}
}
