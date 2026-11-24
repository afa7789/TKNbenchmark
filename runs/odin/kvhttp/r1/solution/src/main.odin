package kvhttp

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:net"
import "core:os"
import "core:strconv"
import "core:sys/posix"
import "core:thread"
import "core:time"

IO_TIMEOUT :: 10 * time.Second

Connection :: struct {
	store:  ^Store,
	socket: net.TCP_Socket,
}

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: app <port>")
		os.exit(2)
	}
	port, ok := strconv.parse_int(os.args[1], 10)
	if !ok || port < 1 || port > 65535 {
		fmt.eprintfln("invalid port: %q", os.args[1])
		os.exit(2)
	}

	// Writes to a peer that already hung up must surface as errors, not kill us.
	posix.signal(.SIGPIPE, auto_cast posix.SIG_IGN)

	listener, listen_err := net.listen_tcp({address = net.IP4_Loopback, port = port})
	if listen_err != nil {
		fmt.eprintfln("listen on 127.0.0.1:%d failed: %v", port, listen_err)
		os.exit(1)
	}
	defer net.close(listener)

	store: Store
	store_init(&store, runtime.heap_allocator())
	defer store_destroy(&store)

	for {
		client, _, accept_err := net.accept_tcp(listener)
		if accept_err != nil {
			fmt.eprintfln("accept failed: %v", accept_err)
			continue
		}
		conn := Connection{store = &store, socket = client}
		thread.create_and_start_with_poly_data(conn, serve_connection, self_cleanup = true)
	}
}

// serve_connection handles a single request and closes the socket. Every
// per-request allocation lives in an arena released when the connection ends.
serve_connection :: proc(conn: Connection) {
	defer net.close(conn.socket)

	arena: virtual.Arena
	if virtual.arena_init_growing(&arena) != nil {
		return
	}
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	context.temp_allocator = context.allocator

	net.set_option(conn.socket, .Receive_Timeout, IO_TIMEOUT)
	net.set_option(conn.socket, .Send_Timeout, IO_TIMEOUT)

	req, parse_err := read_request(conn.socket)
	res: Response
	switch parse_err {
	case .None:
		res = handle(conn.store, req)
	case .Connection_Closed:
		return
	case .Malformed:
		res = {status = 400}
	case .Headers_Too_Large:
		res = {status = 431}
	case .Body_Too_Large:
		res = {status = 413}
	}
	write_response(conn.socket, res)

	// Half-close and drain anything the client is still sending (e.g. an
	// oversized body) so the kernel doesn't reset the connection before the
	// response is read.
	if parse_err != .None {
		net.shutdown(conn.socket, .Send)
		net.set_option(conn.socket, .Receive_Timeout, time.Second)
		scratch: [16 * 1024]byte
		for {
			n, err := net.recv_tcp(conn.socket, scratch[:])
			if err != nil || n == 0 {
				break
			}
		}
	}
}
