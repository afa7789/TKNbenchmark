package server

// routes registers every endpoint. The mux answers 404 for unknown paths and 405 for a known path with an
// unsupported method.
func (s *Server) routes() {
	s.mux.HandleFunc("GET /health", s.handleHealth)

	s.mux.HandleFunc("POST /notes", s.handleCreateNote)
	s.mux.HandleFunc("GET /notes", s.handleListNotes)

	s.mux.HandleFunc("GET /notes/{id}", s.handleGetNote)
	s.mux.HandleFunc("PUT /notes/{id}", s.handleReplaceNote)
	s.mux.HandleFunc("DELETE /notes/{id}", s.handleDeleteNote)

	s.mux.HandleFunc("GET /stats", s.handleStats)
	s.mux.HandleFunc("GET /tags", s.handleTags)
}
