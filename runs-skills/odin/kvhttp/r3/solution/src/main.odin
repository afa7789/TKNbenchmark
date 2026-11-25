package main

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:net"
import "core:os"
import "core:strconv"
import "core:sys/posix"
import "core:thread"
import "core:time"

// Idle clients are dropped after this long so they cannot pin a thread forever.
SOCKET_TIMEOUT :: 30 * time.Second

Connection :: struct {
	sock:  net.TCP_Socket,
	store: ^Store,
}

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintfln("usage: %s <port>", os.args[0])
		os.exit(2)
	}
	port, ok := strconv.parse_int(os.args[1], 10)
	if !ok || port < 1 || port > 65535 {
		fmt.eprintfln("invalid port: %q", os.args[1])
		os.exit(2)
	}

	// Writes to a peer that already hung up must fail with EPIPE, not kill the process.
	posix.signal(.SIGPIPE, auto_cast posix.SIG_IGN)

	store: Store
	store_init(&store, runtime.heap_allocator())
	defer store_destroy(&store)

	listener, err := net.listen_tcp({address = net.IP4_Loopback, port = port}, backlog = 1024)
	if err != nil {
		fmt.eprintfln("listen on 127.0.0.1:%d: %v", port, err)
		os.exit(1)
	}
	defer net.close(listener)

	for {
		client, _, accept_err := net.accept_tcp(listener)
		if accept_err != nil {
			fmt.eprintfln("accept: %v", accept_err)
			continue
		}
		conn := Connection{sock = client, store = &store}
		if thread.create_and_start_with_poly_data(conn, serve_connection, self_cleanup = true) == nil {
			fmt.eprintln("failed to start connection thread")
			net.close(client)
		}
	}
}

// serve_connection handles exactly one request and then closes the socket.
serve_connection :: proc(conn: Connection) {
	defer net.close(conn.sock)

	arena: virtual.Arena
	if virtual.arena_init_growing(&arena) != nil {
		return
	}
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	context.temp_allocator = context.allocator

	_ = net.set_option(conn.sock, .Receive_Timeout, SOCKET_TIMEOUT)
	_ = net.set_option(conn.sock, .Send_Timeout, SOCKET_TIMEOUT)

	res: Response
	req, read_err := read_request(conn.sock)
	switch e in read_err {
	case nil:
		res = handle_request(conn.store, req)
	case Status:
		res = {status = e}
	case net.TCP_Recv_Error, net.TCP_Send_Error:
		return
	}

	if write_response(conn.sock, res) != nil {
		return
	}
	linger_close(conn.sock)
}

// linger_close half-closes the socket and drains any unread request bytes, so
// the kernel does not reset the connection and discard the response we just sent.
linger_close :: proc(sock: net.TCP_Socket) {
	_ = net.shutdown(sock, .Send)
	_ = net.set_option(sock, .Receive_Timeout, time.Second)
	drain: [4096]byte
	for _ in 0 ..< 512 {
		n, err := net.recv_tcp(sock, drain[:])
		if err != nil || n == 0 {
			return
		}
	}
}
