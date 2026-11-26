package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"reflect"
	"strconv"

	"notes/internal/note"
	"notes/internal/store"
)

// maxBodyBytes bounds the size of a request body.
const maxBodyBytes = 1 << 20

// errorBody is the JSON body of every error response.
type errorBody struct {
	Error string `json:"error"`
}

// writeJSON writes v as a JSON response with the given status.
func (s *Server) writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		s.log.Warn("write response", "err", err)
	}
}

// writeError writes a JSON error response with the given status and message.
func (s *Server) writeError(w http.ResponseWriter, status int, msg string) {
	s.writeJSON(w, status, errorBody{Error: msg})
}

// writeNotFound writes the 404 response for a note that does not exist.
func (s *Server) writeNotFound(w http.ResponseWriter) {
	s.writeError(w, http.StatusNotFound, "note not found")
}

// requestError is a malformed request (body or query parameters). Its message is shown to the client.
type requestError struct {
	msg string
}

func (e *requestError) Error() string { return e.msg }

// badRequest returns a *requestError, which writeErr answers with 400.
func badRequest(format string, args ...any) error {
	return &requestError{msg: fmt.Sprintf(format, args...)}
}

// writeErr maps an error to a response: 404 for a missing note, 400 for a malformed request or invalid
// note content, and 500 (logged, with a generic message) for anything else.
func (s *Server) writeErr(w http.ResponseWriter, r *http.Request, err error) {
	var reqErr *requestError
	var valErr *note.ValidationError
	switch {
	case errors.Is(err, store.ErrNotFound):
		s.writeNotFound(w)
	case errors.As(err, &reqErr):
		s.writeError(w, http.StatusBadRequest, reqErr.Error())
	case errors.As(err, &valErr):
		s.writeError(w, http.StatusBadRequest, valErr.Error())
	default:
		s.log.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
		s.writeError(w, http.StatusInternalServerError, "internal error")
	}
}

// noteID parses the {id} path value. ok is false if it is not a positive integer, which callers report as
// 404 like any other note that does not exist.
func noteID(r *http.Request) (id int64, ok bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	return id, err == nil && id > 0
}

// decodeJSON decodes a request body holding exactly one JSON value into dst. Its errors are
// *requestError.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err := dec.Decode(dst); err != nil {
		return describeJSONError(err)
	}
	if _, err := dec.Token(); err != io.EOF {
		return badRequest("request body must hold a single JSON value")
	}
	return nil
}

func describeJSONError(err error) error {
	var typeErr *json.UnmarshalTypeError
	var maxErr *http.MaxBytesError
	switch {
	case errors.As(err, &typeErr) && typeErr.Field != "":
		return badRequest("%s has the wrong type: want %s, got %s", typeErr.Field, jsonType(typeErr.Type), typeErr.Value)
	case errors.As(err, &typeErr):
		return badRequest("request body must be a JSON object")
	case errors.As(err, &maxErr):
		return badRequest("request body exceeds %d bytes", maxErr.Limit)
	case errors.Is(err, io.EOF):
		return badRequest("request body is empty")
	default:
		return badRequest("request body is not valid JSON")
	}
}

// jsonType names the JSON type that decodes into t.
func jsonType(t reflect.Type) string {
	switch t.Kind() {
	case reflect.String:
		return "string"
	case reflect.Bool:
		return "boolean"
	case reflect.Slice, reflect.Array:
		return "array"
	case reflect.Map, reflect.Struct:
		return "object"
	case reflect.Pointer:
		return jsonType(t.Elem())
	default:
		return "number"
	}
}
