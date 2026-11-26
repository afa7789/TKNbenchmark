package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"notes/internal/store"
)

const (
	maxBodyBytes   = 1 << 20
	maxTitleLength = 200
	maxTagLength   = 32
)

// errBadRequest marks validation errors; its message is shown to the client.
type errBadRequest struct{ msg string }

func (e errBadRequest) Error() string { return e.msg }

func badRequest(format string, args ...any) error {
	return errBadRequest{msg: fmt.Sprintf(format, args...)}
}

// decodeNoteInput reads and validates a {title, body?, tags?} request body,
// as used by POST /notes and PUT /notes/{id}. Omitted body and tags become ""
// and []. A returned errBadRequest should be reported as 400.
func decodeNoteInput(w http.ResponseWriter, r *http.Request) (store.NoteInput, error) {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			return store.NoteInput{}, badRequest("request body too large")
		}
		return store.NoteInput{}, badRequest("cannot read request body")
	}
	return parseNoteInput(data)
}

// parseNoteInput validates and normalizes a JSON note object.
func parseNoteInput(data []byte) (store.NoteInput, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil || fields == nil {
		return store.NoteInput{}, badRequest("request body must be a JSON object")
	}

	var in store.NoteInput

	raw, ok := fields["title"]
	if !ok {
		return in, badRequest("title is required")
	}
	if err := unmarshalString(raw, &in.Title); err != nil {
		return in, badRequest("title must be a string")
	}
	in.Title = strings.TrimSpace(in.Title)
	if n := utf8.RuneCountInString(in.Title); n < 1 || n > maxTitleLength {
		return in, badRequest("title must be 1-%d characters", maxTitleLength)
	}

	if raw, ok := fields["body"]; ok {
		if err := unmarshalString(raw, &in.Body); err != nil {
			return in, badRequest("body must be a string")
		}
	}

	in.Tags = []string{}
	if raw, ok := fields["tags"]; ok {
		tags, err := parseTags(raw)
		if err != nil {
			return in, err
		}
		in.Tags = tags
	}
	return in, nil
}

// unmarshalString decodes raw into s, rejecting anything but a JSON string
// (including null, which json.Unmarshal would otherwise accept).
func unmarshalString(raw json.RawMessage, s *string) error {
	if len(raw) == 0 || raw[0] != '"' {
		return errors.New("not a string")
	}
	return json.Unmarshal(raw, s)
}

// parseTags decodes, validates, deduplicates and sorts a JSON array of tags.
func parseTags(raw json.RawMessage) ([]string, error) {
	var items []json.RawMessage
	if len(raw) == 0 || raw[0] != '[' || json.Unmarshal(raw, &items) != nil {
		return nil, badRequest("tags must be an array of strings")
	}
	tags := make([]string, 0, len(items))
	for _, item := range items {
		var tag string
		if err := unmarshalString(item, &tag); err != nil {
			return nil, badRequest("tags must be an array of strings")
		}
		if !ValidTag(tag) {
			return nil, badRequest("invalid tag %q: must be 1-%d characters from a-z, 0-9 and -", tag, maxTagLength)
		}
		tags = append(tags, tag)
	}
	slices.Sort(tags)
	return slices.Compact(tags), nil
}

// ValidTag reports whether tag is 1-32 characters from a-z, 0-9 and '-'.
func ValidTag(tag string) bool {
	if len(tag) < 1 || len(tag) > maxTagLength {
		return false
	}
	for i := 0; i < len(tag); i++ {
		c := tag[i]
		if !('a' <= c && c <= 'z' || '0' <= c && c <= '9' || c == '-') {
			return false
		}
	}
	return true
}

// parseNoteID parses a note id path segment. ok is false unless s is a
// positive decimal integer.
func parseNoteID(s string) (id int64, ok bool) {
	if s == "" || strings.TrimLeft(s, "0123456789") != "" {
		return 0, false
	}
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil || id < 1 {
		return 0, false
	}
	return id, true
}
