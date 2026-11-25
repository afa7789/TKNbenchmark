package main

import "core:fmt"
import vmem "core:mem/virtual"
import "core:net"
import "core:os"
import "core:strconv"
import "core:sys/posix"
import "core:thread"
import "core:time"

IO_TIMEOUT :: 30 * time.Second

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

	// Writes to a peer that has gone away must not kill the process.
	posix.signal(.SIGPIPE, auto_cast posix.SIG_IGN)

	store: Store
	store_init(&store)
	defer store_destroy(&store)

	endpoint := net.Endpoint{address = net.IP4_Loopback, port = port}
	listener, err := net.listen_tcp(endpoint, 1024)
	if err != nil {
		fmt.eprintfln("listen on %v failed: %v", net.endpoint_to_string(endpoint, context.temp_allocator), err)
		os.exit(1)
	}
	defer net.close(listener)

	for {
		sock, _, aerr := net.accept_tcp(listener)
		if aerr != nil {
			continue
		}
		conn := new(Connection)
		conn^ = {sock = sock, store = &store}
		thread.create_and_start_with_poly_data(conn, serve_connection, self_cleanup = true)
	}
}

// serve_connection handles a single request and closes the connection.
serve_connection :: proc(conn: ^Connection) {
	sock, store := conn.sock, conn.store
	free(conn)
	defer net.close(sock)

	net.set_option(sock, .Receive_Timeout, IO_TIMEOUT)
	net.set_option(sock, .Send_Timeout, IO_TIMEOUT)

	// Every allocation for this request lives in one arena, freed at once.
	arena: vmem.Arena
	if vmem.arena_init_growing(&arena) != nil {
		return
	}
	defer vmem.arena_destroy(&arena)
	context.allocator = vmem.arena_allocator(&arena)

	res: Response
	req, rerr := read_request(sock)
	switch rerr {
	case .None:             res = handle(store, req)
	case .Closed:           return
	case .Malformed:        res = {status = .Bad_Request}
	case .Header_Too_Large: res = {status = .Header_Too_Large}
	case .Body_Too_Large:   res = {status = .Content_Too_Large}
	case .Unsupported:      res = {status = .Not_Implemented}
	}

	if write_response(sock, res) == nil {
		net.shutdown(sock, .Send)
	}
}

