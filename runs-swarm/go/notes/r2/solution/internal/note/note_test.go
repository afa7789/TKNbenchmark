package note

import (
	"slices"
	"strings"
	"testing"
)

func TestParseInputValid(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want Input
	}{
		{"title only", `{"title":"first"}`, Input{Title: "first", Body: "", Tags: []string{}}},
		{"trims spaces", `{"title":"  second  ","body":"text"}`, Input{Title: "second", Body: "text", Tags: []string{}}},
		{"dedup and sort tags", `{"title":"x","tags":["work","b-2","work"]}`, Input{Title: "x", Tags: []string{"b-2", "work"}}},
		{"empty tags", `{"title":"x","tags":[]}`, Input{Title: "x", Tags: []string{}}},
		{"unknown fields ignored", `{"title":"x","id":9}`, Input{Title: "x", Tags: []string{}}},
		{"max title runes", `{"title":"` + strings.Repeat("é", MaxTitleLen) + `"}`, Input{Title: strings.Repeat("é", MaxTitleLen), Tags: []string{}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseInput([]byte(tt.in))
			if err != nil {
				t.Fatalf("ParseInput(%s) error: %v", tt.in, err)
			}
			if got.Title != tt.want.Title || got.Body != tt.want.Body || !slices.Equal(got.Tags, tt.want.Tags) || got.Tags == nil {
				t.Fatalf("ParseInput(%s) = %#v, want %#v", tt.in, got, tt.want)
			}
		})
	}
}

func TestParseInputInvalid(t *testing.T) {
	inputs := []string{
		``,
		`{"title": `,
		`[]`,
		`null`,
		`"title"`,
		`{}`,
		`{"title":null}`,
		`{"title":3}`,
		`{"title":"   "}`,
		`{"title":"` + strings.Repeat("a", MaxTitleLen+1) + `"}`,
		`{"title":"x","body":3}`,
		`{"title":"x","body":null}`,
		`{"title":"x","tags":null}`,
		`{"title":"x","tags":"a"}`,
		`{"title":"x","tags":[1]}`,
		`{"title":"x","tags":["Bad"]}`,
		`{"title":"x","tags":[""]}`,
		`{"title":"x","tags":["` + strings.Repeat("a", MaxTagLen+1) + `"]}`,
		`{"title":"x"} trailing`,
	}
	for _, in := range inputs {
		_, err := ParseInput([]byte(in))
		if err == nil {
			t.Errorf("ParseInput(%q) succeeded, want error", in)
			continue
		}
		if !IsValidation(err) {
			t.Errorf("ParseInput(%q) error %v is not a ValidationError", in, err)
		}
	}
}

func TestValidTag(t *testing.T) {
	for _, tag := range []string{"a", "b-2", "0", strings.Repeat("z", MaxTagLen)} {
		if !ValidTag(tag) {
			t.Errorf("ValidTag(%q) = false, want true", tag)
		}
	}
	for _, tag := range []string{"", "A", "a_b", "a b", "é", strings.Repeat("z", MaxTagLen+1)} {
		if ValidTag(tag) {
			t.Errorf("ValidTag(%q) = true, want false", tag)
		}
	}
}
