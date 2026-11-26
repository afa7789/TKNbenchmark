// Package note defines the note domain type and the rules a note's content must satisfy.
package note

import (
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"
)

// Limits on note content.
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

// Input is the client-supplied content of a note, as accepted on create and on full replacement.
type Input struct {
	Title string
	Body  string
	Tags  []string
}

// ValidationError reports note content that breaks the rules. Its message is safe to show to clients.
type ValidationError struct {
	msg string
}

func (e *ValidationError) Error() string { return e.msg }

func invalid(format string, args ...any) error {
	return &ValidationError{msg: fmt.Sprintf(format, args...)}
}

// Normalize returns the canonical form of in: the title without leading and trailing whitespace, and the
// tags deduplicated and sorted ascending (never nil). It returns a *ValidationError if the result is invalid.
func (in Input) Normalize() (Input, error) {
	title := strings.TrimSpace(in.Title)
	if n := utf8.RuneCountInString(title); n < 1 || n > MaxTitleLen {
		return Input{}, invalid("title must be 1 to %d characters", MaxTitleLen)
	}
	tags := make([]string, 0, len(in.Tags))
	for _, t := range in.Tags {
		if !ValidTag(t) {
			return Input{}, invalid("invalid tag %q: must be 1 to %d characters from a-z, 0-9 and -", t, MaxTagLen)
		}
		tags = append(tags, t)
	}
	slices.Sort(tags)
	return Input{Title: title, Body: in.Body, Tags: slices.Compact(tags)}, nil
}

// ValidTag reports whether t is a well-formed tag: 1 to MaxTagLen characters from a-z, 0-9 and -.
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
