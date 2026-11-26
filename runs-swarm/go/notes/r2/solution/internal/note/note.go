// Package note defines the note model and the validation of client input.
package note

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"
)

// Limits from the specification.
const (
	MaxTitleLen = 200
	MaxTagLen   = 32
)

// Note is a stored note as returned to clients.
type Note struct {
	ID    int64    `json:"id"`
	Title string   `json:"title"`
	Body  string   `json:"body"`
	Tags  []string `json:"tags"`
}

// Input is the validated, normalized content of a create or replace request.
type Input struct {
	Title string
	Body  string
	Tags  []string // deduplicated, sorted ascending, never nil
}

// ValidationError reports client input that does not satisfy the specification.
type ValidationError struct {
	Msg string
}

func (e *ValidationError) Error() string { return e.Msg }

func invalid(format string, args ...any) error {
	return &ValidationError{Msg: fmt.Sprintf(format, args...)}
}

// IsValidation reports whether err is (or wraps) a *ValidationError.
func IsValidation(err error) bool {
	var ve *ValidationError
	return errors.As(err, &ve)
}

var jsonNull = []byte("null")

// ParseInput decodes and validates a JSON request body of the form
// {"title": string, "body"?: string, "tags"?: [string, ...]}.
// Unknown fields are ignored. All failures are *ValidationError.
func ParseInput(data []byte) (Input, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil || fields == nil {
		return Input{}, invalid("request body must be a JSON object")
	}

	var in Input

	rawTitle, ok := fields["title"]
	if !ok {
		return Input{}, invalid("title is required")
	}
	if err := decodeString(rawTitle, &in.Title); err != nil {
		return Input{}, invalid("title must be a string")
	}
	in.Title = strings.Trim(in.Title, " ")
	if n := utf8.RuneCountInString(in.Title); n < 1 || n > MaxTitleLen {
		return Input{}, invalid("title must be 1-%d characters", MaxTitleLen)
	}

	if rawBody, ok := fields["body"]; ok {
		if err := decodeString(rawBody, &in.Body); err != nil {
			return Input{}, invalid("body must be a string")
		}
	}

	in.Tags = []string{}
	if rawTags, ok := fields["tags"]; ok {
		var tags []string
		if bytes.Equal(bytes.TrimSpace(rawTags), jsonNull) || json.Unmarshal(rawTags, &tags) != nil {
			return Input{}, invalid("tags must be an array of strings")
		}
		normalized, err := NormalizeTags(tags)
		if err != nil {
			return Input{}, err
		}
		in.Tags = normalized
	}

	return in, nil
}

// decodeString decodes a JSON string, rejecting null and every other type.
func decodeString(raw json.RawMessage, dst *string) error {
	if bytes.Equal(bytes.TrimSpace(raw), jsonNull) {
		return errors.New("null")
	}
	return json.Unmarshal(raw, dst)
}

// NormalizeTags validates each tag and returns them deduplicated and sorted.
func NormalizeTags(tags []string) ([]string, error) {
	for _, t := range tags {
		if !ValidTag(t) {
			return nil, invalid("invalid tag %q: tags are 1-%d characters from a-z, 0-9 and -", t, MaxTagLen)
		}
	}
	out := slices.Clone(tags)
	slices.Sort(out)
	out = slices.Compact(out)
	if out == nil {
		out = []string{}
	}
	return out, nil
}

// ValidTag reports whether t is 1-32 characters from a-z, 0-9 and '-'.
func ValidTag(t string) bool {
	if len(t) < 1 || len(t) > MaxTagLen {
		return false
	}
	for i := 0; i < len(t); i++ {
		c := t[i]
		if (c < 'a' || c > 'z') && (c < '0' || c > '9') && c != '-' {
			return false
		}
	}
	return true
}
