package main

import "core:bytes"
import "core:net"
import "core:strconv"
import "core:strings"

MAX_HEADER_BYTES :: 16 * 1024
MAX_BODY_BYTES :: 1024 * 1024

HEADER_END :: "\r\n\r\n"

Request :: struct {
	method: string,
	path:   string,
	body:   []byte,
}

Response :: struct {
	status:       Status,
	content_type: string,
	body:         []byte,
}

Status :: enum {
	OK,
	Created,
	No_Content,
	Bad_Request,
	Not_Found,
	Method_Not_Allowed,
	Payload_Too_Large,
	Header_Fields_Too_Large,
	Internal_Server_Error,
	Not_Implemented,
	HTTP_Version_Not_Supported,
}

STATUS_LINES := [Status]string {
	.OK                         = "200 OK",
	.Created                    = "201 Created",
	.No_Content                 = "204 No Content",
	.Bad_Request                = "400 Bad Request",
	.Not_Found                  = "404 Not Found",
	.Method_Not_Allowed         = "405 Method Not Allowed",
	.Payload_Too_Large          = "413 Content Too Large",
	.Header_Fields_Too_Large    = "431 Request Header Fields Too Large",
	.Internal_Server_Error      = "500 Internal Server Error",
	.Not_Implemented            = "501 Not Implemented",
	.HTTP_Version_Not_Supported = "505 HTTP Version Not Supported",
}

// Read_Error is either a transport failure (no response is possible) or a
// protocol error that should be answered with the given status.
Read_Error :: union {
	Status,
	net.TCP_Recv_Error,
	net.TCP_Send_Error,
}

// read_request reads one HTTP/1.x request from `sock`. All returned memory
// (strings and body) is allocated with `allocator`.
read_request :: proc(sock: net.TCP_Socket, allocator := context.allocator) -> (req: Request, err: Read_Error) {
	buf := make([dynamic]byte, 0, 4096, allocator)
	header_end := -1
	for header_end < 0 {
		if len(buf) >= MAX_HEADER_BYTES {
			return {}, Status.Header_Fields_Too_Large
		}
		scan_from := max(len(buf) - (len(HEADER_END) - 1), 0)
		n := recv_append(sock, &buf, MAX_HEADER_BYTES - len(buf)) or_return
		if n == 0 {
			return {}, net.TCP_Recv_Error.Connection_Closed
		}
		if i := bytes.index(buf[scan_from:], transmute([]byte)string(HEADER_END)); i >= 0 {
			header_end = scan_from + i
		}
	}

	head := string(buf[:header_end])
	leftover := buf[header_end + len(HEADER_END):]

	request_line, _, header_lines := cut(head, "\r\n")
	method, _, rest := cut(request_line, " ")
	target, _, version := cut(rest, " ")
	if method == "" || target == "" || !strings.has_prefix(version, "HTTP/") {
		return {}, Status.Bad_Request
	}
	if !strings.has_prefix(version, "HTTP/1.") {
		return {}, Status.HTTP_Version_Not_Supported
	}
	req.method = method
	req.path = target

	content_length := 0
	has_length := false
	expect_continue := false
	for line in strings.split_lines_iterator(&header_lines) {
		name, found, value := cut(line, ":")
		if !found || name == "" {
			return {}, Status.Bad_Request
		}
		value = strings.trim_space(value)
		switch {
		case strings.equal_fold(name, "content-length"):
			n, ok := strconv.parse_int(value, 10)
			if !ok || n < 0 || (has_length && n != content_length) {
				return {}, Status.Bad_Request
			}
			content_length, has_length = n, true
		case strings.equal_fold(name, "transfer-encoding"):
			return {}, Status.Not_Implemented
		case strings.equal_fold(name, "expect"):
			expect_continue = strings.equal_fold(value, "100-continue")
		}
	}

	if content_length > MAX_BODY_BYTES {
		return {}, Status.Payload_Too_Large
	}
	if len(leftover) > content_length {
		// Pipelined requests are not supported; this connection serves one request.
		return {}, Status.Bad_Request
	}

	body := make([]byte, content_length, allocator)
	have := copy(body, leftover)
	if have < content_length && expect_continue {
		net.send_tcp(sock, transmute([]byte)string("HTTP/1.1 100 Continue\r\n\r\n")) or_return
	}
	for have < content_length {
		n := net.recv_tcp(sock, body[have:]) or_return
		if n == 0 {
			return {}, net.TCP_Recv_Error.Connection_Closed
		}
		have += n
	}
	req.body = body
	return req, nil
}

// write_response sends the status line, headers and body. The connection is
// always closed after one response, which is advertised to the client.
write_response :: proc(sock: net.TCP_Socket, res: Response) -> net.Network_Error {
	b := strings.builder_make(0, 256, context.temp_allocator)
	strings.write_string(&b, "HTTP/1.1 ")
	strings.write_string(&b, STATUS_LINES[res.status])
	strings.write_string(&b, "\r\nContent-Length: ")
	strings.write_int(&b, len(res.body))
	if res.content_type != "" {
		strings.write_string(&b, "\r\nContent-Type: ")
		strings.write_string(&b, res.content_type)
	}
	strings.write_string(&b, "\r\nConnection: close\r\n\r\n")

	net.send_tcp(sock, b.buf[:]) or_return
	if len(res.body) > 0 {
		net.send_tcp(sock, res.body) or_return
	}
	return nil
}

// recv_append receives up to `limit` bytes and appends them to `buf`.
@(private = "file")
recv_append :: proc(sock: net.TCP_Socket, buf: ^[dynamic]byte, limit: int) -> (n: int, err: net.TCP_Recv_Error) {
	old_len := len(buf)
	resize(buf, old_len + min(limit, max(cap(buf) - old_len, 4096)))
	n, err = net.recv_tcp(sock, buf[old_len:])
	resize(buf, old_len + max(n, 0))
	return
}

@(private = "file")
cut :: proc(s, sep: string) -> (before: string, found: bool, after: string) {
	i := strings.index(s, sep)
	if i < 0 {
		return s, false, ""
	}
	return s[:i], true, s[i + len(sep):]
}
