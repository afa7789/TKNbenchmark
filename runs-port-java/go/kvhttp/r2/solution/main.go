// Command kvhttp serves an in-memory key-value store over HTTP on 127.0.0.1.
//
// Usage:
//
//	app <port>
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"kvhttp/internal/kv"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: app <port>")
		os.Exit(2)
	}
	port, err := strconv.ParseUint(os.Args[1], 10, 16)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid port: %s\n", os.Args[1])
		os.Exit(2)
	}
	if err := run(net.JoinHostPort("127.0.0.1", strconv.FormatUint(port, 10))); err != nil {
		log.Fatal(err)
	}
}

func run(addr string) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	srv := &http.Server{
		Addr:              addr,
		Handler:           kv.NewHandler(kv.NewStore()),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    64 << 10,
	}

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}

	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()

	select {
	case err := <-errc:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}
