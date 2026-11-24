// kvhttp: an in-memory HTTP/1.1 key-value server.
package kvhttp

import "base:runtime"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:sync/chan"
import "core:sys/posix"
import "core:thread"
import "core:time"

WORKER_COUNT :: 128
ACCEPT_QUEUE :: 1024
SOCKET_TIMEOUT :: 10 * time.Second

Server :: struct {
	store: Store,
	queue: chan.Chan(net.TCP_Socket),
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

	// Writes to a peer that already hung up must not kill the process.
	posix.signal(.SIGPIPE, auto_cast posix.SIG_IGN)

	listener, listen_err := net.listen_tcp({address = net.IP4_Loopback, port = port}, backlog = 1024)
	if listen_err != nil {
		fmt.eprintfln("listen on 127.0.0.1:%d: %v", port, listen_err)
		os.exit(1)
	}
	defer net.close(listener)

	server: Server
	store_init(&server.store)
	defer store_destroy(&server.store)

	queue_err: runtime.Allocator_Error
	server.queue, queue_err = chan.create_buffered(chan.Chan(net.TCP_Socket), ACCEPT_QUEUE, context.allocator)
	if queue_err != nil {
		fmt.eprintfln("create connection queue: %v", queue_err)
		os.exit(1)
	}
	defer chan.destroy(server.queue)

	workers: [WORKER_COUNT]^thread.Thread
	for &w in workers {
		w = thread.create_and_start_with_poly_data(&server, worker)
	}

	for {
		client, _, accept_err := net.accept_tcp(listener)
		if accept_err != nil {
			// Transient failures (EMFILE, ECONNABORTED, ...) must not stop the server.
			time.sleep(10 * time.Millisecond)
			continue
		}
		if !chan.send(server.queue, client) {
			net.close(client)
			break
		}
	}

	chan.close(server.queue)
	thread.join_multiple(..workers[:])
	for w in workers {
		thread.destroy(w)
	}
}

@(private = "file")
worker :: proc(server: ^Server) {
	for {
		client, ok := chan.recv(server.queue)
		if !ok {
			return
		}
		serve_connection(server, client)
		free_all(context.temp_allocator)
	}
}

// serve_connection handles a single request and closes the connection.
@(private = "file")
serve_connection :: proc(server: ^Server, client: net.TCP_Socket) {
	defer net.close(client)

	_ = net.set_option(client, .Receive_Timeout, SOCKET_TIMEOUT)
	_ = net.set_option(client, .Send_Timeout, SOCKET_TIMEOUT)
	_ = net.set_option(client, .TCP_Nodelay, true)

	head_buf: [MAX_HEADER_BYTES]byte
	body_allocator := server.store.allocator

	req, read_err := read_request(client, head_buf[:], body_allocator)
	switch read_err {
	case .None:
	case .Closed:
		return
	case .Malformed, .Timeout, .Too_Large, .Header_Large, .Unsupported, .Out_Of_Memory:
		_ = write_response(client, {status = read_error_status(read_err)})
		discard_input(client)
		return
	}

	res, body_consumed := handle(&server.store, req)
	if !body_consumed {
		delete(req.body, body_allocator)
	}
	_ = write_response(client, res)
}

// discard_input half-closes the socket and drains unread request bytes so the
// peer receives the error response instead of a connection reset.
@(private = "file")
discard_input :: proc(client: net.TCP_Socket) {
	_ = net.shutdown(client, .Send)
	_ = net.set_option(client, .Receive_Timeout, 1 * time.Second)

	scratch: [16 * 1024]byte
	budget := 4 * MAX_BODY_BYTES
	for budget > 0 {
		n, err := net.recv_tcp(client, scratch[:])
		if err != nil || n == 0 {
			return
		}
		budget -= n
	}
}
