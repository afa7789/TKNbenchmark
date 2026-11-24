package kvhttp

import "core:bytes"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"

MAX_HEADER_BYTES :: 16 * 1024
MAX_BODY_BYTES :: 1024 * 1024

Request :: struct {
	method: string,
	path:   string,
	// Allocated with the store's allocator so PUT can hand it over without copying.
	body:   []byte,
}

Status :: enum u16 {
	OK                      = 200,
	Created                 = 201,
	No_Content              = 204,
	Bad_Request             = 400,
	Not_Found               = 404,
	Method_Not_Allowed      = 405,
	Request_Timeout         = 408,
	Payload_Too_Large       = 413,
	Header_Fields_Too_Large = 431,
	Internal_Server_Error   = 500,
	Not_Implemented         = 501,
}

status_reason :: proc(s: Status) -> string {
	switch s {
	case .OK:                      return "OK"
	case .Created:                 return "Created"
	case .No_Content:              return "No Content"
	case .Bad_Request:             return "Bad Request"
	case .Not_Found:               return "Not Found"
	case .Method_Not_Allowed:      return "Method Not Allowed"
	case .Request_Timeout:         return "Request Timeout"
	case .Payload_Too_Large:       return "Payload Too Large"
	case .Header_Fields_Too_Large: return "Request Header Fields Too Large"
	case .Internal_Server_Error:   return "Internal Server Error"
	case .Not_Implemented:         return "Not Implemented"
	}
	return "Unknown"
}

Response :: struct {
	status:       Status,
	content_type: string,
	body:         []byte,
	allow:        string,
}

Read_Error :: enum {
	None,
	Closed,       // peer went away or the socket failed; nothing can be sent
	Malformed,    // 400
	Timeout,      // 408
	Too_Large,    // 413
	Header_Large, // 431
	Unsupported,  // 501
	Out_Of_Memory, // 500
}

read_error_status :: proc(e: Read_Error) -> Status {
	#partial switch e {
	case .Malformed:     return .Bad_Request
	case .Timeout:       return .Request_Timeout
	case .Too_Large:     return .Payload_Too_Large
	case .Header_Large:  return .Header_Fields_Too_Large
	case .Unsupported:   return .Not_Implemented
	}
	return .Internal_Server_Error
}

// read_request reads one HTTP/1.1 request from `sock`. The head is parsed out of
// `head_buf`, so `method` and `path` alias it. The body is allocated with
// `body_allocator` and owned by the caller.
read_request :: proc(
	sock: net.TCP_Socket,
	head_buf: []byte,
	body_allocator := context.allocator,
) -> (
	req: Request,
	err: Read_Error,
) {
	filled := 0
	head_end := -1
	for head_end < 0 {
		if filled == len(head_buf) {
			return {}, .Header_Large
		}
		n, recv_err := net.recv_tcp(sock, head_buf[filled:])
		if recv_err != nil {
			return {}, recv_error(recv_err, filled)
		}
		if n == 0 {
			return {}, .Closed if filled == 0 else .Malformed
		}
		// Rescan a few bytes before the new data in case the terminator straddles reads.
		scan_from := max(filled - 3, 0)
		filled += n
		if i := bytes.index(head_buf[scan_from:filled], {'\r', '\n', '\r', '\n'}); i >= 0 {
			head_end = scan_from + i
		}
	}

	head := string(head_buf[:head_end])
	leftover := head_buf[head_end + 4:filled]

	content_length := parse_head(head, &req) or_return
	if content_length > MAX_BODY_BYTES {
		return {}, .Too_Large
	}
	if content_length == 0 {
		return req, .None
	}

	body, alloc_err := make([]byte, content_length, body_allocator)
	if alloc_err != nil {
		return {}, .Out_Of_Memory
	}
	defer if err != .None {
		delete(body, body_allocator)
	}

	got := copy(body, leftover)
	for got < content_length {
		n, recv_err := net.recv_tcp(sock, body[got:])
		if recv_err != nil {
			return {}, recv_error(recv_err, 1)
		}
		if n == 0 {
			return {}, .Closed
		}
		got += n
	}
	req.body = body
	return req, .None
}

@(private = "file")
recv_error :: proc(e: net.TCP_Recv_Error, received: int) -> Read_Error {
	if e == .Timeout && received > 0 {
		return .Timeout
	}
	return .Closed
}

// parse_head parses the request line and headers, filling method and path.
@(private = "file")
parse_head :: proc(head: string, req: ^Request) -> (content_length: int, err: Read_Error) {
	rest := head
	request_line, _ := strings.split_iterator(&rest, "\r\n")

	parts := request_line
	method, _ := strings.split_iterator(&parts, " ")
	target, _ := strings.split_iterator(&parts, " ")
	version := parts
	if method == "" || target == "" || !strings.has_prefix(version, "HTTP/1.") {
		return 0, .Malformed
	}
	if !strings.has_prefix(target, "/") {
		return 0, .Malformed
	}
	// Queries are not part of routing.
	if q := strings.index_byte(target, '?'); q >= 0 {
		target = target[:q]
	}
	req.method = method
	req.path = target

	have_length := false
	for line in strings.split_iterator(&rest, "\r\n") {
		colon := strings.index_byte(line, ':')
		if colon <= 0 {
			return 0, .Malformed
		}
		name := line[:colon]
		value := strings.trim_space(line[colon + 1:])

		switch {
		case strings.equal_fold(name, "Content-Length"):
			n, ok := strconv.parse_int(value, 10)
			if !ok || n < 0 || !is_all_digits(value) {
				return 0, .Malformed
			}
			if have_length && n != content_length {
				return 0, .Malformed
			}
			have_length = true
			content_length = n
		case strings.equal_fold(name, "Transfer-Encoding"):
			if !strings.equal_fold(value, "identity") {
				return 0, .Unsupported
			}
		}
	}
	return content_length, .None
}

@(private = "file")
is_all_digits :: proc(s: string) -> bool {
	if s == "" {
		return false
	}
	for c in transmute([]byte)s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// write_response sends a complete response and announces that the connection
// will be closed afterwards.
write_response :: proc(sock: net.TCP_Socket, res: Response) -> net.TCP_Send_Error {
	head_buf: [512]byte
	b := strings.builder_from_bytes(head_buf[:])

	fmt.sbprintf(&b, "HTTP/1.1 %d %s\r\n", u16(res.status), status_reason(res.status))
	if res.content_type != "" {
		fmt.sbprintf(&b, "Content-Type: %s\r\n", res.content_type)
	}
	if res.allow != "" {
		fmt.sbprintf(&b, "Allow: %s\r\n", res.allow)
	}
	fmt.sbprintf(&b, "Content-Length: %d\r\nConnection: close\r\n\r\n", len(res.body))

	head := strings.to_string(b)
	if len(res.body) > 0 && len(res.body) <= 4096 {
		// Coalesce small responses into one write.
		buf: [512 + 4096]byte
		n := copy(buf[:], head)
		n += copy(buf[n:], res.body)
		net.send_tcp(sock, buf[:n]) or_return
		return nil
	}
	net.send_tcp(sock, transmute([]byte)head) or_return
	if len(res.body) > 0 {
		net.send_tcp(sock, res.body) or_return
	}
	return nil
}
