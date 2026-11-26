package api

import (
	"slices"
	"strings"
	"testing"
)

func TestParseNoteInput(t *testing.T) {
	tests := []struct {
		name    string
		body    string
		want    noteInput
		wantErr bool
	}{
		{name: "minimal", body: `{"title":"a"}`, want: noteInput{Title: "a", Tags: []string{}}},
		{name: "trim and dedupe", body: ` {"title":"  x  ","body":"b","tags":["z","a","z"]} `, want: noteInput{Title: "x", Body: "b", Tags: []string{"a", "z"}}},
		{name: "200 runes", body: `{"title":"` + strings.Repeat("é", 200) + `"}`, want: noteInput{Title: strings.Repeat("é", 200), Tags: []string{}}},
		{name: "201 runes", body: `{"title":"` + strings.Repeat("a", 201) + `"}`, wantErr: true},
		{name: "invalid json", body: `{"title":`, wantErr: true},
		{name: "trailing data", body: `{"title":"a"} {}`, wantErr: true},
		{name: "array", body: `[]`, wantErr: true},
		{name: "null", body: `null`, wantErr: true},
		{name: "empty", body: ``, wantErr: true},
		{name: "missing title", body: `{}`, wantErr: true},
		{name: "blank title", body: `{"title":"   "}`, wantErr: true},
		{name: "numeric title", body: `{"title":1}`, wantErr: true},
		{name: "null title", body: `{"title":null}`, wantErr: true},
		{name: "numeric body", body: `{"title":"a","body":3}`, wantErr: true},
		{name: "tags not array", body: `{"title":"a","tags":"x"}`, wantErr: true},
		{name: "tag not string", body: `{"title":"a","tags":[1]}`, wantErr: true},
		{name: "tag uppercase", body: `{"title":"a","tags":["Bad"]}`, wantErr: true},
		{name: "tag empty", body: `{"title":"a","tags":[""]}`, wantErr: true},
		{name: "tag too long", body: `{"title":"a","tags":["` + strings.Repeat("a", 33) + `"]}`, wantErr: true},
		{name: "tag max length", body: `{"title":"a","tags":["` + strings.Repeat("a", 32) + `"]}`, want: noteInput{Title: "a", Tags: []string{strings.Repeat("a", 32)}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseNoteInput([]byte(tt.body))
			if (err != nil) != tt.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tt.wantErr)
			}
			if err != nil {
				return
			}
			if got.Title != tt.want.Title || got.Body != tt.want.Body || !slices.Equal(got.Tags, tt.want.Tags) {
				t.Fatalf("got %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestParsePositiveID(t *testing.T) {
	for s, want := range map[string]bool{"1": true, "42": true, "0": false, "-1": false, "+1": false, "abc": false, "": false, "1.0": false, "99999999999999999999": false} {
		if _, ok := parsePositiveID(s); ok != want {
			t.Errorf("parsePositiveID(%q) ok = %v, want %v", s, ok, want)
		}
	}
}
