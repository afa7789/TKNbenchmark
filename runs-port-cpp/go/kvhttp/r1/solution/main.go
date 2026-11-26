// Command app is an HTTP/1.1 in-memory key/value server.
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
		fmt.Fprintf(os.Stderr, "usage: %s <port>\n", os.Args[0])
		os.Exit(2)
	}
	port, err := strconv.ParseUint(os.Args[1], 10, 16)
	if err != nil || port == 0 {
		fmt.Fprintf(os.Stderr, "invalid port: %s\n", os.Args[1])
		os.Exit(2)
	}
	if err := run(net.JoinHostPort("127.0.0.1", strconv.FormatUint(port, 10))); err != nil {
		log.Fatalf("fatal: %v", err)
	}
}

func run(addr string) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}

	srv := &http.Server{
		Handler:           newHandler(kv.NewStore()),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    64 << 10,
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
