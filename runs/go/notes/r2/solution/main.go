// Command app serves a small SQLite-backed notes store over HTTP.
//
// Usage: NOTES_DB=/path/to/notes.db app <port>
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

	"notes/internal/notes"
	"notes/internal/server"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	if err := run(log, os.Args[1:]); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: app <port>")
	}
	port, err := strconv.ParseUint(args[0], 10, 16)
	if err != nil {
		return fmt.Errorf("invalid port %q", args[0])
	}
	dbPath := os.Getenv("NOTES_DB")
	if dbPath == "" {
		return errors.New("NOTES_DB is not set")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	store, err := notes.Open(ctx, dbPath)
	if err != nil {
		return err
	}
	defer store.Close()

	ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.FormatUint(port, 10)))
	if err != nil {
		return err
	}
	srv := &http.Server{
		Handler:           server.New(store, log),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       time.Minute,
		WriteTimeout:      time.Minute,
		IdleTimeout:       2 * time.Minute,
	}

	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()
	log.Info("listening", "addr", ln.Addr().String(), "db", dbPath)

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}
