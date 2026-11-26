package server

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"
)

const (
	maxTitleLen = 200
	maxTagLen   = 32
)

// noteInput is a validated create/replace request.
type noteInput struct {
	Title string
	Body  string
	Tags  []string
}

// parseNoteInput decodes and validates a note request body.
func parseNoteInput(data []byte) (noteInput, error) {
	var fields map[string]json.RawMessage
	dec := json.NewDecoder(bytes.NewReader(data))
	if err := dec.Decode(&fields); err != nil {
		return noteInput{}, errors.New("request body must be a JSON object")
	}
	if fields == nil {
		return noteInput{}, errors.New("request body must be a JSON object")
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return noteInput{}, errors.New("request body must be a single JSON object")
	}

	var in noteInput

	rawTitle, ok := fields["title"]
	if !ok {
		return noteInput{}, errors.New("title is required")
	}
	title, ok := decodeString(rawTitle)
	if !ok {
		return noteInput{}, errors.New("title must be a string")
	}
	in.Title = strings.TrimSpace(title)
	if n := utf8.RuneCountInString(in.Title); n < 1 || n > maxTitleLen {
		return noteInput{}, fmt.Errorf("title must be 1-%d characters", maxTitleLen)
	}

	if raw, ok := fields["body"]; ok {
		body, ok := decodeString(raw)
		if !ok {
			return noteInput{}, errors.New("body must be a string")
		}
		in.Body = body
	}

	in.Tags = []string{}
	if raw, ok := fields["tags"]; ok {
		tags, err := decodeTags(raw)
		if err != nil {
			return noteInput{}, err
		}
		in.Tags = tags
	}
	return in, nil
}

// decodeString decodes raw as a JSON string; null and other types are rejected.
func decodeString(raw json.RawMessage) (string, bool) {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || raw[0] != '"' {
		return "", false
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return "", false
	}
	return s, true
}

func decodeTags(raw json.RawMessage) ([]string, error) {
	raw = bytes.TrimSpace(raw)
	var items []json.RawMessage
	if len(raw) == 0 || raw[0] != '[' || json.Unmarshal(raw, &items) != nil {
		return nil, errors.New("tags must be an array of strings")
	}
	tags := make([]string, 0, len(items))
	for _, item := range items {
		tag, ok := decodeString(item)
		if !ok {
			return nil, errors.New("tags must be an array of strings")
		}
		if !validTag(tag) {
			return nil, fmt.Errorf("invalid tag %q: must be 1-%d characters from a-z, 0-9 and -", tag, maxTagLen)
		}
		tags = append(tags, tag)
	}
	slices.Sort(tags)
	return slices.Compact(tags), nil
}

func validTag(tag string) bool {
	if len(tag) < 1 || len(tag) > maxTagLen {
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

// parsePositiveID parses a path segment as a note id: a positive decimal integer.
func parsePositiveID(s string) (int64, bool) {
	if s == "" || strings.Trim(s, "0123456789") != "" {
		return 0, false
	}
	id, err := strconv.ParseInt(s, 10, 64)
	return id, err == nil && id > 0
}

// parseInt parses an optionally signed decimal integer query parameter.
func parseInt(s string) (int64, bool) {
	digits := strings.TrimPrefix(s, "-")
	if digits == "" || strings.Trim(digits, "0123456789") != "" {
		return 0, false
	}
	n, err := strconv.ParseInt(s, 10, 64)
	return n, err == nil
}
