// Command app serves the notes HTTP API: ./app <port>, with the SQLite
// database path in the NOTES_DB environment variable.
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

	"notes/internal/httpapi"
	"notes/internal/store"
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
	if err != nil || port == 0 {
		return fmt.Errorf("invalid port %q", args[0])
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
		Handler:           httpapi.New(st, log),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
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
