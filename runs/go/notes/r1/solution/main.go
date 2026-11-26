// Command app serves a small SQLite-backed notes store over HTTP.
//
// Usage: NOTES_DB=/path/to/notes.db ./app <port>
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"notes/internal/api"
	"notes/internal/store"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	if err := run(log); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	if len(os.Args) != 2 {
		return fmt.Errorf("usage: %s <port>", os.Args[0])
	}
	port, err := strconv.ParseUint(os.Args[1], 10, 16)
	if err != nil {
		return fmt.Errorf("invalid port %q", os.Args[1])
	}
	dbPath := os.Getenv("NOTES_DB")
	if dbPath == "" {
		return errors.New("NOTES_DB is not set")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	st, err := store.Open(ctx, dbPath)
	if err != nil {
		return err
	}
	defer st.Close()

	ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.FormatUint(port, 10)))
	if err != nil {
		return err
	}
	srv := &http.Server{
		Handler:           api.New(st, log),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()
	log.Info("listening", "addr", ln.Addr().String(), "db", dbPath)

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}
