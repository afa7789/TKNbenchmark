package notes

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

func TestParseInput(t *testing.T) {
	tests := []struct {
		name    string
		body    string
		want    Input
		wantErr bool
	}{
		{name: "minimal", body: `{"title":"x"}`, want: Input{Title: "x", Tags: []string{}}},
		{name: "trimmed", body: `{"title":"  hi  ","body":"b"}`, want: Input{Title: "hi", Body: "b", Tags: []string{}}},
		{name: "tags sorted and deduplicated", body: `{"title":"x","tags":["b","a-1","b"]}`, want: Input{Title: "x", Tags: []string{"a-1", "b"}}},
		{name: "max title", body: `{"title":"` + strings.Repeat("é", 200) + `"}`, want: Input{Title: strings.Repeat("é", 200), Tags: []string{}}},
		{name: "title too long", body: `{"title":"` + strings.Repeat("a", 201) + `"}`, wantErr: true},
		{name: "blank title", body: `{"title":"   "}`, wantErr: true},
		{name: "missing title", body: `{}`, wantErr: true},
		{name: "null title", body: `{"title":null}`, wantErr: true},
		{name: "numeric title", body: `{"title":1}`, wantErr: true},
		{name: "array", body: `[]`, wantErr: true},
		{name: "null", body: `null`, wantErr: true},
		{name: "truncated", body: `{"title": `, wantErr: true},
		{name: "trailing garbage", body: `{"title":"x"} x`, wantErr: true},
		{name: "body not string", body: `{"title":"x","body":3}`, wantErr: true},
		{name: "body null", body: `{"title":"x","body":null}`, wantErr: true},
		{name: "tags not array", body: `{"title":"x","tags":"a"}`, wantErr: true},
		{name: "tag not string", body: `{"title":"x","tags":[1]}`, wantErr: true},
		{name: "tag uppercase", body: `{"title":"x","tags":["Bad"]}`, wantErr: true},
		{name: "tag empty", body: `{"title":"x","tags":[""]}`, wantErr: true},
		{name: "tag too long", body: `{"title":"x","tags":["` + strings.Repeat("a", 33) + `"]}`, wantErr: true},
		{name: "tag max length", body: `{"title":"x","tags":["` + strings.Repeat("a", 32) + `"]}`, want: Input{Title: "x", Tags: []string{strings.Repeat("a", 32)}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseInput([]byte(tt.body))
			if tt.wantErr {
				var ve *ValidationError
				if !errors.As(err, &ve) {
					t.Fatalf("want ValidationError, got %v (input %+v)", err, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got.Title != tt.want.Title || got.Body != tt.want.Body || !slices.Equal(got.Tags, tt.want.Tags) || got.Tags == nil {
				t.Fatalf("got %+v, want %+v", got, tt.want)
			}
		})
	}
}
