package main

import "core:bytes"
import "core:net"
import "core:strconv"
import "core:strings"

MAX_HEADER_BYTES :: 64 * 1024
MAX_BODY_BYTES :: 1024 * 1024
// Oversized bodies are read and discarded up to this many bytes so that the
// client receives the error response instead of a connection reset.
MAX_DRAIN_BYTES :: 64 * 1024 * 1024

Request :: struct {
	method: string,
	path:   string,
	body:   []byte,
}

Status :: enum {
	OK                    = 200,
	Created               = 201,
	No_Content            = 204,
	Bad_Request           = 400,
	Not_Found             = 404,
	Method_Not_Allowed    = 405,
	Content_Too_Large     = 413,
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
	case .Content_Too_Large:     return "Content Too Large"
	case .Header_Too_Large:      return "Request Header Fields Too Large"
	case .Internal_Server_Error: return "Internal Server Error"
	case .Not_Implemented:       return "Not Implemented"
	}
	return "Unknown"
}

Response :: struct {
	status:       Status,
	content_type: string,
	allow:        string,
	body:         []byte,
}

Read_Error :: enum {
	None,
	Closed,         // peer closed or socket error before a full request arrived
	Malformed,      // syntactically invalid request
	Header_Too_Large,
	Body_Too_Large,
	Unsupported,    // e.g. Transfer-Encoding
}

// read_request reads one HTTP/1.1 request from the socket. All memory comes
// from context.allocator; strings in the returned Request view that memory.
read_request :: proc(sock: net.TCP_Socket) -> (req: Request, err: Read_Error) {
	buf := make([dynamic]byte, 0, 4096)
	chunk: [4096]byte

	header_end := -1
	for header_end < 0 {
		n, rerr := net.recv_tcp(sock, chunk[:])
		if rerr != nil || n == 0 {
			return {}, .Closed
		}
		// Only rescan the region that could contain a new terminator.
		scan_from := max(0, len(buf) - 3)
		append(&buf, ..chunk[:n])
		if i := bytes.index(buf[scan_from:], {'\r', '\n', '\r', '\n'}); i >= 0 {
			header_end = scan_from + i
		} else if len(buf) > MAX_HEADER_BYTES {
			return {}, .Header_Too_Large
		}
	}
	if header_end > MAX_HEADER_BYTES {
		return {}, .Header_Too_Large
	}

	head := string(buf[:header_end])
	request_line, _ := strings.split_iterator(&head, "\r\n")
	parts := request_line
	method, _ := strings.split_iterator(&parts, " ")
	target, _ := strings.split_iterator(&parts, " ")
	version := parts
	if method == "" || target == "" || !strings.has_prefix(version, "HTTP/1.") {
		return {}, .Malformed
	}
	req.method = method
	req.path = target

	content_length := 0
	for line in strings.split_iterator(&head, "\r\n") {
		colon := strings.index_byte(line, ':')
		if colon <= 0 {
			return {}, .Malformed
		}
		name := line[:colon]
		value := strings.trim_space(line[colon + 1:])
		switch {
		case strings.equal_fold(name, "Content-Length"):
			cl, ok := strconv.parse_int(value, 10)
			if !ok || cl < 0 {
				return {}, .Malformed
			}
			content_length = cl
		case strings.equal_fold(name, "Transfer-Encoding"):
			return {}, .Unsupported
		}
	}

	body_start := header_end + 4
	if content_length > MAX_BODY_BYTES {
		drain(sock, content_length - (len(buf) - body_start))
		return req, .Body_Too_Large
	}

	body := make([]byte, content_length)
	have := copy(body, buf[body_start:])
	for have < content_length {
		n, rerr := net.recv_tcp(sock, body[have:])
		if rerr != nil || n == 0 {
			return {}, .Closed
		}
		have += n
	}
	req.body = body
	return req, .None
}

// drain reads and discards up to `remaining` bytes (bounded by MAX_DRAIN_BYTES).
@(private = "file")
drain :: proc(sock: net.TCP_Socket, count: int) {
	remaining := min(count, MAX_DRAIN_BYTES)
	scratch: [16 * 1024]byte
	for remaining > 0 {
		n, err := net.recv_tcp(sock, scratch[:min(remaining, len(scratch))])
		if err != nil || n == 0 {
			return
		}
		remaining -= n
	}
}

write_response :: proc(sock: net.TCP_Socket, res: Response) -> net.TCP_Send_Error {
	b := strings.builder_make(0, 256)
	defer strings.builder_destroy(&b)

	code := int(res.status)
	strings.write_string(&b, "HTTP/1.1 ")
	strings.write_int(&b, code)
	strings.write_byte(&b, ' ')
	strings.write_string(&b, status_text(res.status))
	strings.write_string(&b, "\r\nContent-Length: ")
	strings.write_int(&b, len(res.body))
	strings.write_string(&b, "\r\nConnection: close\r\n")
	if res.content_type != "" {
		strings.write_string(&b, "Content-Type: ")
		strings.write_string(&b, res.content_type)
		strings.write_string(&b, "\r\n")
	}
	if res.allow != "" {
		strings.write_string(&b, "Allow: ")
		strings.write_string(&b, res.allow)
		strings.write_string(&b, "\r\n")
	}
	strings.write_string(&b, "\r\n")

	// Small bodies go out in the same write as the header.
	if len(res.body) <= 16 * 1024 {
		strings.write_bytes(&b, res.body)
		_, err := net.send_tcp(sock, b.buf[:])
		return err
	}
	net.send_tcp(sock, b.buf[:]) or_return
	_, err := net.send_tcp(sock, res.body)
	return err
}
