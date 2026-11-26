// Package notes holds the note model, its validation rules and a SQLite-backed store.
package notes

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"slices"
	"strings"
	"unicode/utf8"
)

const (
	MaxTitleLen = 200
	MaxTagLen   = 32
)

// Note is a stored note.
type Note struct {
	ID    int64    `json:"id"`
	Title string   `json:"title"`
	Body  string   `json:"body"`
	Tags  []string `json:"tags"`
}

// Input is the validated content of a note as supplied by a client.
type Input struct {
	Title string
	Body  string
	Tags  []string
}

// ValidationError describes why client input was rejected.
type ValidationError struct{ Msg string }

func (e *ValidationError) Error() string { return e.Msg }

func invalid(format string, args ...any) error {
	return &ValidationError{Msg: fmt.Sprintf(format, args...)}
}

// ParseInput decodes and validates a JSON note payload. Errors are *ValidationError.
func ParseInput(data []byte) (Input, error) {
	var fields map[string]json.RawMessage
	dec := json.NewDecoder(bytes.NewReader(data))
	if err := dec.Decode(&fields); err != nil || fields == nil {
		return Input{}, invalid("request body must be a JSON object")
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return Input{}, invalid("request body must be a single JSON object")
	}

	var in Input
	raw, ok := fields["title"]
	if !ok {
		return Input{}, invalid("title is required")
	}
	if !decodeString(raw, &in.Title) {
		return Input{}, invalid("title must be a string")
	}
	in.Title = strings.TrimSpace(in.Title)
	if n := utf8.RuneCountInString(in.Title); n < 1 || n > MaxTitleLen {
		return Input{}, invalid("title must be 1-%d characters", MaxTitleLen)
	}

	if raw, ok := fields["body"]; ok && !decodeString(raw, &in.Body) {
		return Input{}, invalid("body must be a string")
	}

	in.Tags = []string{}
	if raw, ok := fields["tags"]; ok {
		tags, err := parseTags(raw)
		if err != nil {
			return Input{}, err
		}
		in.Tags = tags
	}
	return in, nil
}

// decodeString decodes raw into s, rejecting anything but a JSON string (including null).
func decodeString(raw json.RawMessage, s *string) bool {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || raw[0] != '"' {
		return false
	}
	return json.Unmarshal(raw, s) == nil
}

func parseTags(raw json.RawMessage) ([]string, error) {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || raw[0] != '[' {
		return nil, invalid("tags must be an array of strings")
	}
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, invalid("tags must be an array of strings")
	}
	tags := make([]string, 0, len(items))
	for _, item := range items {
		var tag string
		if !decodeString(item, &tag) {
			return nil, invalid("tags must be an array of strings")
		}
		if !ValidTag(tag) {
			return nil, invalid("invalid tag %q: must be 1-%d characters from a-z, 0-9 and -", tag, MaxTagLen)
		}
		tags = append(tags, tag)
	}
	slices.Sort(tags)
	return slices.Compact(tags), nil
}

// ValidTag reports whether tag is 1-32 characters from a-z, 0-9 and '-'.
func ValidTag(tag string) bool {
	if len(tag) < 1 || len(tag) > MaxTagLen {
		return false
	}
	for i := 0; i < len(tag); i++ {
		c := tag[i]
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') {
			return false
		}
	}
	return true
}
