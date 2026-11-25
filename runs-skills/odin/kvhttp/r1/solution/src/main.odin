package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:thread"
import "core:time"

// Each worker blocks in accept() on the shared listening socket, so this is
// also the number of connections served concurrently.
WORKER_COUNT :: 128
CLIENT_TIMEOUT :: 30 * time.Second

Server :: struct {
	listener: net.TCP_Socket,
	store:    Store,
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

	// A peer closing early must surface as a send error, not kill the process.
	posix.signal(.SIGPIPE, auto_cast posix.SIG_IGN)

	server: Server
	store_init(&server.store)
	defer store_destroy(&server.store)

	endpoint := net.Endpoint{address = net.IP4_Loopback, port = port}
	listener, err := net.listen_tcp(endpoint, backlog = 1024)
	if err != nil {
		fmt.eprintfln("listen on %v failed: %v", net.endpoint_to_string(endpoint, context.temp_allocator), err)
		os.exit(1)
	}
	defer net.close(listener)
	server.listener = listener

	workers: [WORKER_COUNT]^thread.Thread
	for &w in workers {
		w = thread.create_and_start_with_poly_data(&server, worker)
	}
	thread.join_multiple(..workers[:])
	for w in workers {
		thread.destroy(w)
	}
}

worker :: proc(server: ^Server) {
	for {
		client, _, err := net.accept_tcp(server.listener)
		if err != nil {
			if err == .Would_Block || err == .Interrupted || err == .Aborted {
				continue
			}
			// Typically fd exhaustion; back off instead of spinning.
			time.sleep(10 * time.Millisecond)
			continue
		}
		serve_connection(server, client)
		free_all(context.temp_allocator)
	}
}

serve_connection :: proc(server: ^Server, client: net.TCP_Socket) {
	defer net.close(client)
	_ = net.set_option(client, .Receive_Timeout, CLIENT_TIMEOUT)
	_ = net.set_option(client, .Send_Timeout, CLIENT_TIMEOUT)

	req, rerr := read_request(client, context.temp_allocator)
	res: Response
	switch rerr {
	case .None:
		res = route(&server.store, req)
	case .Closed:
		return
	case .Malformed:
		res = {status = 400}
	case .Header_Too_Large:
		res = {status = 431}
	case .Body_Too_Large:
		res = {status = 413}
	case .Not_Implemented:
		res = {status = 501}
	}
	write_response(client, res)
}

route :: proc(store: ^Store, req: Request) -> Response {
	KV_PREFIX :: "/kv/"

	switch {
	case req.path == "/health":
		if req.method != "GET" {
			return {status = 405, allow = "GET"}
		}
		return {status = 200, content_type = "text/plain", body = transmute([]byte)string("ok")}

	case req.path == "/kv":
		if req.method != "GET" {
			return {status = 405, allow = "GET"}
		}
		return list_keys(store)

	case strings.has_prefix(req.path, KV_PREFIX):
		key := req.path[len(KV_PREFIX):]
		if !valid_key(key) {
			return {status = 400}
		}
		switch req.method {
		case "GET":
			value, found := store_get(store, key, context.temp_allocator)
			if !found {
				return {status = 404}
			}
			return {status = 200, content_type = "application/octet-stream", body = value}
		case "PUT":
			switch store_put(store, key, req.body) {
			case .Created:
				return {status = 201}
			case .Replaced:
				return {status = 200}
			}
		case "DELETE":
			return {status = 204 if store_delete(store, key) else 404}
		}
		return {status = 405, allow = "GET, PUT, DELETE"}
	}
	return {status = 404}
}

list_keys :: proc(store: ^Store) -> Response {
	keys := store_keys(store, context.temp_allocator)

	b := strings.builder_make(context.temp_allocator)
	strings.write_byte(&b, '[')
	for k, i in keys {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		// Valid keys never contain characters that need JSON escaping.
		strings.write_byte(&b, '"')
		strings.write_string(&b, k)
		strings.write_byte(&b, '"')
	}
	strings.write_byte(&b, ']')
	return {status = 200, content_type = "application/json", body = b.buf[:]}
}

valid_key :: proc(key: string) -> bool {
	if len(key) < 1 || len(key) > 64 {
		return false
	}
	for c in transmute([]byte)key {
		switch c {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '_', '-':
		case:
			return false
		}
	}
	return true
}
