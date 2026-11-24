// kvhttp: a small in-memory HTTP/1.1 key-value server.
package kvhttp

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:net"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:thread"
import "core:time"

MAX_KEY_LEN    :: 64
MAX_VALUE_SIZE :: 1 << 20
MAX_HEAD_SIZE  :: 64 * 1024
RECV_CHUNK     :: 16 * 1024
IO_TIMEOUT     :: 30 * time.Second

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

// Shared, thread-safe key-value store. Keys and values are owned by
// `allocator`, independent of whatever allocator the calling request uses.
Store :: struct {
	lock:      sync.RW_Mutex,
	data:      map[string][]byte,
	allocator: mem.Allocator,
}

store_init :: proc(s: ^Store, allocator := context.allocator) {
	s.allocator = allocator
	s.data = make(map[string][]byte, allocator = allocator)
}

// Inserts or replaces `key`. Returns true if the key was newly created.
store_put :: proc(s: ^Store, key: string, value: []byte) -> (created: bool) {
	owned_value := slice.clone(value, s.allocator)

	sync.guard(&s.lock)
	if old, ok := &s.data[key]; ok {
		delete(old^, s.allocator)
		old^ = owned_value
		return false
	}
	s.data[strings.clone(key, s.allocator)] = owned_value
	return true
}

// Returns a copy of the stored value allocated with `allocator`.
store_get :: proc(s: ^Store, key: string, allocator := context.allocator) -> (value: []byte, found: bool) {
	sync.shared_guard(&s.lock)
	v := s.data[key] or_return
	return slice.clone(v, allocator), true
}

store_delete :: proc(s: ^Store, key: string) -> (deleted: bool) {
	sync.guard(&s.lock)
	k, v := delete_key(&s.data, key)
	if k == "" {
		return false
	}
	delete(k, s.allocator)
	delete(v, s.allocator)
	return true
}

// Returns all keys, sorted ascending, cloned into `allocator`.
store_keys :: proc(s: ^Store, allocator := context.allocator) -> []string {
	keys: [dynamic]string
	{
		sync.shared_guard(&s.lock)
		keys = make([dynamic]string, 0, len(s.data), allocator)
		for k in s.data {
			append(&keys, strings.clone(k, allocator))
		}
	}
	slice.sort(keys[:])
	return keys[:]
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

Status :: enum {
	OK                    = 200,
	Created               = 201,
	No_Content            = 204,
	Bad_Request           = 400,
	Not_Found             = 404,
	Method_Not_Allowed    = 405,
	Payload_Too_Large     = 413,
	Header_Too_Large      = 431,
	Internal_Server_Error = 500,
	Not_Implemented       = 501,
}

status_text :: proc(s: Status) -> string {
	switch s {
	case .OK:                    return "OK"
	case .Created:               return "Created"
	case .No_Content:            return "No Content"
	case .Bad_Request:           return "Bad Request"
	case .Not_Found:             return "Not Found"
	case .Method_Not_Allowed:    return "Method Not Allowed"
	case .Payload_Too_Large:     return "Payload Too Large"
	case .Header_Too_Large:      return "Request Header Fields Too Large"
	case .Internal_Server_Error: return "Internal Server Error"
	case .Not_Implemented:       return "Not Implemented"
	}
	return "Unknown"
}

Request :: struct {
	method: string,
	path:   string,
	body:   []byte,
}

Response :: struct {
	status:       Status,
	content_type: string,
	allow:        string,
	body:         []byte,
}

Read_Error :: enum {
	None,
	Disconnected,
	Malformed,
	Head_Too_Large,
	Body_Too_Large,
	Unsupported,
}

// Reads one request from `sock`. All memory comes from `context.allocator`.
read_request :: proc(sock: net.TCP_Socket) -> (req: Request, err: Read_Error) {
	buf := make([dynamic]byte, 0, RECV_CHUNK)
	head_end := -1
	scanned := 0

	for head_end < 0 {
		if len(buf) >= MAX_HEAD_SIZE {
			return {}, .Head_Too_Large
		}
		old_len := len(buf)
		resize(&buf, old_len + RECV_CHUNK)
		n, recv_err := net.recv_tcp(sock, buf[old_len:])
		resize(&buf, old_len + max(n, 0))
		if recv_err != nil || n <= 0 {
			return {}, .Disconnected
		}
		// Resume the terminator search slightly before the new data.
		start := max(scanned - 3, 0)
		if i := strings.index(string(buf[start:]), "\r\n\r\n"); i >= 0 {
			head_end = start + i
		}
		scanned = len(buf)
	}
	if head_end > MAX_HEAD_SIZE {
		return {}, .Head_Too_Large
	}

	head := string(buf[:head_end])
	request_line, _, header_block := strings.partition(head, "\r\n")

	parts := strings.split(request_line, " ")
	if len(parts) != 3 || len(parts[0]) == 0 || len(parts[1]) == 0 || !strings.has_prefix(parts[2], "HTTP/1.") {
		return {}, .Malformed
	}
	req.method = parts[0]
	req.path = parts[1]
	if q := strings.index_byte(req.path, '?'); q >= 0 {
		req.path = req.path[:q]
	}

	content_length := 0
	have_length := false
	for line in strings.split_lines_iterator(&header_block) {
		name, sep, value := strings.partition(line, ":")
		if sep == "" {
			return {}, .Malformed
		}
		name = strings.trim_space(name)
		value = strings.trim_space(value)
		switch {
		case strings.equal_fold(name, "Content-Length"):
			n, ok := strconv.parse_int(value, 10)
			if !ok || n < 0 || (have_length && n != content_length) {
				return {}, .Malformed
			}
			content_length = n
			have_length = true
		case strings.equal_fold(name, "Transfer-Encoding"):
			if !strings.equal_fold(value, "identity") {
				return {}, .Unsupported
			}
		}
	}
	if content_length > MAX_VALUE_SIZE {
		return {}, .Body_Too_Large
	}

	body_start := head_end + 4
	body := make([]byte, content_length)
	copied := copy(body, buf[body_start:])

	for copied < content_length {
		n, recv_err := net.recv_tcp(sock, body[copied:])
		if recv_err != nil || n <= 0 {
			return {}, .Disconnected
		}
		copied += n
	}
	req.body = body
	return req, .None
}

write_response :: proc(sock: net.TCP_Socket, res: Response) {
	sb := strings.builder_make(0, 256)
	fmt.sbprintf(&sb, "HTTP/1.1 %d %s\r\n", int(res.status), status_text(res.status))
	fmt.sbprintf(&sb, "Content-Length: %d\r\n", len(res.body))
	if res.content_type != "" {
		fmt.sbprintf(&sb, "Content-Type: %s\r\n", res.content_type)
	}
	if res.allow != "" {
		fmt.sbprintf(&sb, "Allow: %s\r\n", res.allow)
	}
	strings.write_string(&sb, "Connection: close\r\n\r\n")

	if _, err := net.send_tcp(sock, sb.buf[:]); err != nil {
		return
	}
	if len(res.body) > 0 {
		net.send_tcp(sock, res.body)
	}
}

text :: proc(status: Status, body: string = "") -> Response {
	return {status = status, content_type = "text/plain; charset=utf-8" if body != "" else "", body = transmute([]byte)body}
}

method_not_allowed :: proc(allow: string) -> Response {
	r := text(.Method_Not_Allowed, "method not allowed")
	r.allow = allow
	return r
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

is_valid_key :: proc(key: string) -> bool {
	if len(key) == 0 || len(key) > MAX_KEY_LEN {
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

handle :: proc(store: ^Store, req: Request) -> Response {
	switch {
	case req.path == "/health":
		if req.method != "GET" {
			return method_not_allowed("GET")
		}
		return text(.OK, "ok")

	case req.path == "/kv":
		if req.method != "GET" {
			return method_not_allowed("GET")
		}
		keys := store_keys(store)
		sb := strings.builder_make(0, 2 + len(keys) * 8)
		strings.write_byte(&sb, '[')
		for k, i in keys {
			if i > 0 {
				strings.write_byte(&sb, ',')
			}
			// Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
			strings.write_byte(&sb, '"')
			strings.write_string(&sb, k)
			strings.write_byte(&sb, '"')
		}
		strings.write_byte(&sb, ']')
		return {status = .OK, content_type = "application/json", body = sb.buf[:]}

	case strings.has_prefix(req.path, "/kv/"):
		key := req.path[len("/kv/"):]
		if !is_valid_key(key) {
			return text(.Bad_Request, "invalid key")
		}
		switch req.method {
		case "GET":
			value, found := store_get(store, key)
			if !found {
				return text(.Not_Found, "not found")
			}
			return {status = .OK, content_type = "application/octet-stream", body = value}
		case "PUT":
			created := store_put(store, key, req.body)
			return {status = .Created if created else .OK}
		case "DELETE":
			if !store_delete(store, key) {
				return text(.Not_Found, "not found")
			}
			return {status = .No_Content}
		case:
			return method_not_allowed("GET, PUT, DELETE")
		}
	}
	return text(.Not_Found, "not found")
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

serve_connection :: proc(store: ^Store, sock: net.TCP_Socket) {
	defer net.close(sock)

	arena: virtual.Arena
	if virtual.arena_init_growing(&arena) != nil {
		write_response(sock, text(.Internal_Server_Error))
		return
	}
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	context.temp_allocator = context.allocator

	net.set_option(sock, .Receive_Timeout, IO_TIMEOUT)
	net.set_option(sock, .Send_Timeout, IO_TIMEOUT)

	req, err := read_request(sock)
	switch err {
	case .None:
		write_response(sock, handle(store, req))
	case .Disconnected:
	case .Malformed:
		write_response(sock, text(.Bad_Request, "bad request"))
	case .Head_Too_Large:
		write_response(sock, text(.Header_Too_Large, "request header too large"))
	case .Body_Too_Large:
		write_response(sock, text(.Payload_Too_Large, "value too large"))
	case .Unsupported:
		write_response(sock, text(.Not_Implemented, "unsupported transfer encoding"))
	}
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

	// Writes to peers that hung up must surface as errors, not kill the process.
	posix.signal(.SIGPIPE, auto_cast posix.SIG_IGN)

	endpoint := net.Endpoint{address = net.IP4_Loopback, port = port}
	listener, listen_err := net.listen_tcp(endpoint, backlog = 1024)
	if listen_err != nil {
		fmt.eprintfln("listen on %s failed: %v", net.endpoint_to_string(endpoint), listen_err)
		os.exit(1)
	}
	defer net.close(listener)

	store := new(Store)
	store_init(store)

	for {
		client, _, accept_err := net.accept_tcp(listener)
		if accept_err != nil {
			fmt.eprintfln("accept failed: %v", accept_err)
			continue
		}
		t := thread.create_and_start_with_poly_data2(store, client, serve_connection, self_cleanup = true)
		if t == nil {
			write_response(client, text(.Internal_Server_Error))
			net.close(client)
		}
	}
}
