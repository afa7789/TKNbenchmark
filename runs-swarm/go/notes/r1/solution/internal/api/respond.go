package api

import (
	"encoding/json"
	"net/http"
)

// writeJSON writes v as a JSON response with the given status.
func (s *Server) writeJSON(w http.ResponseWriter, status int, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		s.log.Error("encode response", "err", err)
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write(append(data, '\n'))
}

type errorBody struct {
	Error string `json:"error"`
}

// writeError writes a JSON error response {"error": msg}.
func (s *Server) writeError(w http.ResponseWriter, status int, msg string) {
	s.writeJSON(w, status, errorBody{Error: msg})
}

// writeInternalError logs err and responds with 500.
func (s *Server) writeInternalError(w http.ResponseWriter, r *http.Request, err error) {
	s.log.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
	s.writeError(w, http.StatusInternalServerError, "internal error")
}
