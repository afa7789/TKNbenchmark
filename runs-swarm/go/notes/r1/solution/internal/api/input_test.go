package api

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

func TestParseNoteInput(t *testing.T) {
	in, err := parseNoteInput([]byte(`{"title":"  hi  ","body":"b","tags":["z","a-1","z"],"extra":1}`))
	if err != nil {
		t.Fatal(err)
	}
	if in.Title != "hi" || in.Body != "b" || !slices.Equal(in.Tags, []string{"a-1", "z"}) {
		t.Fatalf("got %+v", in)
	}

	in, err = parseNoteInput([]byte(`{"title":"x"}`))
	if err != nil {
		t.Fatal(err)
	}
	if in.Body != "" || in.Tags == nil || len(in.Tags) != 0 {
		t.Fatalf("defaults: got %+v", in)
	}
}

func TestParseNoteInputErrors(t *testing.T) {
	for _, body := range []string{
		``, `{"title": `, `[]`, `null`, `"x"`, `{}`, `{"title":"x"} {}`,
		`{"title":null}`, `{"title":3}`, `{"title":"   "}`, `{"title":"` + strings.Repeat("é", 201) + `"}`,
		`{"title":"x","body":3}`, `{"title":"x","body":null}`,
		`{"title":"x","tags":"a"}`, `{"title":"x","tags":null}`, `{"title":"x","tags":[1]}`,
		`{"title":"x","tags":["Bad"]}`, `{"title":"x","tags":[""]}`,
		`{"title":"x","tags":["` + strings.Repeat("a", 33) + `"]}`,
	} {
		_, err := parseNoteInput([]byte(body))
		if _, ok := errors.AsType[errBadRequest](err); !ok {
			t.Errorf("%s: got err %v, want errBadRequest", body, err)
		}
	}
	if _, err := parseNoteInput([]byte(`{"title":"` + strings.Repeat("é", 200) + `"}`)); err != nil {
		t.Errorf("200-character title rejected: %v", err)
	}
}

func TestParseNoteID(t *testing.T) {
	for s, want := range map[string]bool{
		"1": true, "42": true, "007": true,
		"": false, "0": false, "-1": false, "+1": false, "abc": false, "1.5": false,
		"99999999999999999999": false,
	} {
		if _, ok := parseNoteID(s); ok != want {
			t.Errorf("parseNoteID(%q) ok = %v, want %v", s, ok, want)
		}
	}
}
