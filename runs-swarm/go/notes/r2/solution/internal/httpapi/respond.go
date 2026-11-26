package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	"notes/internal/note"
)

// maxBodyBytes bounds request bodies. The specification sets no limit on the
// size of a note body, so this is generous; it only guards against abuse.
const maxBodyBytes = 16 << 20

type errorBody struct {
	Error string `json:"error"`
}

// writeJSON sends v as a JSON response with the given status.
func (s *Server) writeJSON(w http.ResponseWriter, status int, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		s.log.Error("encode response", "err", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(append(data, '\n'))
}

// writeError sends {"error": msg} with the given status.
func (s *Server) writeError(w http.ResponseWriter, status int, msg string) {
	s.writeJSON(w, status, errorBody{Error: msg})
}

// serverError logs err and sends a generic 500 response.
func (s *Server) serverError(w http.ResponseWriter, r *http.Request, err error) {
	s.log.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
	s.writeError(w, http.StatusInternalServerError, "internal server error")
}

// notFound sends a 404 response.
func (s *Server) notFound(w http.ResponseWriter) {
	s.writeError(w, http.StatusNotFound, "note not found")
}

// noteID parses the {id} path value as a positive decimal integer. On failure
// it writes a 404 response (an invalid id names no note) and returns false.
func (s *Server) noteID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	raw := r.PathValue("id")
	for i := 0; i < len(raw); i++ {
		if raw[i] < '0' || raw[i] > '9' {
			s.notFound(w)
			return 0, false
		}
	}
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || id <= 0 {
		s.notFound(w)
		return 0, false
	}
	return id, true
}

// readInput reads and validates a {title, body?, tags?} request body. On
// failure it writes a 4xx response and returns false.
func (s *Server) readInput(w http.ResponseWriter, r *http.Request) (note.Input, bool) {
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		if maxErr := (*http.MaxBytesError)(nil); errors.As(err, &maxErr) {
			s.writeError(w, http.StatusRequestEntityTooLarge, "request body too large")
		} else {
			s.writeError(w, http.StatusBadRequest, "could not read request body")
		}
		return note.Input{}, false
	}
	in, err := note.ParseInput(data)
	if err != nil {
		s.writeError(w, http.StatusBadRequest, err.Error())
		return note.Input{}, false
	}
	return in, true
}
