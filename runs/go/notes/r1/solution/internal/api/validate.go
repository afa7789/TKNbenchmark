package api

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
	maxTitleLen = 200
	maxTagLen   = 32
)

// noteInput is a validated create/update request.
type noteInput struct {
	Title string
	Body  string
	Tags  []string
}

// validationError is a client error reported as 400.
type validationError struct{ msg string }

func (e *validationError) Error() string { return e.msg }

func invalid(format string, args ...any) error {
	return &validationError{msg: fmt.Sprintf(format, args...)}
}

// parseNoteInput decodes and validates a note request body.
func parseNoteInput(data []byte) (noteInput, error) {
	var fields map[string]json.RawMessage
	dec := json.NewDecoder(bytes.NewReader(data))
	if err := dec.Decode(&fields); err != nil || fields == nil {
		return noteInput{}, invalid("request body must be a JSON object")
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return noteInput{}, invalid("request body must be a single JSON object")
	}

	var in noteInput

	raw, ok := fields["title"]
	if !ok {
		return noteInput{}, invalid("title is required")
	}
	title, ok := decodeString(raw)
	if !ok {
		return noteInput{}, invalid("title must be a string")
	}
	in.Title = strings.TrimSpace(title)
	if n := utf8.RuneCountInString(in.Title); n < 1 || n > maxTitleLen {
		return noteInput{}, invalid("title must be 1-%d characters", maxTitleLen)
	}

	if raw, ok := fields["body"]; ok {
		if in.Body, ok = decodeString(raw); !ok {
			return noteInput{}, invalid("body must be a string")
		}
	}

	in.Tags = []string{}
	if raw, ok := fields["tags"]; ok {
		tags, err := parseTags(raw)
		if err != nil {
			return noteInput{}, err
		}
		in.Tags = tags
	}
	return in, nil
}

// decodeString decodes raw as a JSON string; null and other types are rejected.
func decodeString(raw json.RawMessage) (string, bool) {
	if len(raw) == 0 || raw[0] != '"' {
		return "", false
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return "", false
	}
	return s, true
}

func parseTags(raw json.RawMessage) ([]string, error) {
	if len(raw) == 0 || raw[0] != '[' {
		return nil, invalid("tags must be an array of strings")
	}
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, invalid("tags must be an array of strings")
	}
	tags := make([]string, 0, len(items))
	for _, item := range items {
		t, ok := decodeString(item)
		if !ok {
			return nil, invalid("tags must be an array of strings")
		}
		if !validTag(t) {
			return nil, invalid("invalid tag %q: must be 1-%d characters from a-z, 0-9 and -", t, maxTagLen)
		}
		tags = append(tags, t)
	}
	slices.Sort(tags)
	return slices.Compact(tags), nil
}

func validTag(t string) bool {
	if len(t) < 1 || len(t) > maxTagLen {
		return false
	}
	for i := 0; i < len(t); i++ {
		c := t[i]
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') {
			return false
		}
	}
	return true
}

// parsePositiveID parses a note id path segment: decimal digits only, value ≥ 1.
func parsePositiveID(s string) (int64, bool) {
	n, ok := parseDigits(s)
	return n, ok && n >= 1
}

// parseDigits parses a non-empty run of ASCII digits that fits in int64.
func parseDigits(s string) (int64, bool) {
	if s == "" {
		return 0, false
	}
	var n int64
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		d := int64(c - '0')
		if n > (1<<63-1-d)/10 {
			return 0, false
		}
		n = n*10 + d
	}
	return n, true
}

// parseInt parses an optionally negative decimal integer that fits in int64.
func parseInt(s string) (int64, bool) {
	if rest, ok := strings.CutPrefix(s, "-"); ok {
		n, ok := parseDigits(rest)
		return -n, ok
	}
	return parseDigits(s)
}
