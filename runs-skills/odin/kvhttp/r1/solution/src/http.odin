package main

import "core:bytes"
import "core:net"
import "core:strconv"
import "core:strings"

MAX_HEADER_BYTES :: 64 * 1024
MAX_BODY_BYTES :: 1024 * 1024
RECV_CHUNK :: 64 * 1024

Request :: struct {
	method: string,
	path:   string,
	body:   []byte,
}

Read_Error :: enum {
	None,
	Closed, // peer went away or socket error: nothing to answer
	Malformed, // 400
	Header_Too_Large, // 431
	Body_Too_Large, // 413
	Not_Implemented, // 501 (e.g. chunked transfer encoding)
}

Response :: struct {
	status:       int,
	content_type: string,
	allow:        string, // for 405 responses
	body:         []byte,
}

// Reads one HTTP/1.1 request from `sock`. All memory comes from `allocator`;
// the returned strings and body are views into that memory.
read_request :: proc(sock: net.TCP_Socket, allocator := context.allocator) -> (req: Request, err: Read_Error) {
	buf := make([dynamic]byte, 0, 4096, allocator)
	chunk: [RECV_CHUNK]byte

	header_end := -1
	for header_end < 0 {
		n, rerr := net.recv_tcp(sock, chunk[:])
		if rerr != nil || n == 0 {
			return {}, .Closed
		}
		search_from := max(0, len(buf) - 3)
		append(&buf, ..chunk[:n])
		if i := bytes.index(buf[search_from:], {'\r', '\n', '\r', '\n'}); i >= 0 {
			header_end = search_from + i
		} else if len(buf) > MAX_HEADER_BYTES {
			return {}, .Header_Too_Large
		}
	}
	if header_end > MAX_HEADER_BYTES {
		return {}, .Header_Too_Large
	}

	head := string(buf[:header_end])
	request_line, _, rest := strings.partition(head, "\r\n")

	parts := strings.split_n(request_line, " ", 3, allocator)
	if len(parts) != 3 || parts[0] == "" || parts[1] == "" || !strings.has_prefix(parts[2], "HTTP/") {
		return {}, .Malformed
	}
	req.method = parts[0]
	req.path = parts[1]

	content_length := 0
	has_length := false
	for line in strings.split_iterator(&rest, "\r\n") {
		name, sep, value := strings.partition(line, ":")
		if sep == "" {
			return {}, .Malformed
		}
		value = strings.trim_space(value)
		switch {
		case strings.equal_fold(name, "Content-Length"):
			n, ok := strconv.parse_int(value, 10)
			if !ok || n < 0 || (has_length && n != content_length) {
				return {}, .Malformed
			}
			content_length, has_length = n, true
		case strings.equal_fold(name, "Transfer-Encoding"):
			if !strings.equal_fold(value, "identity") {
				return {}, .Not_Implemented
			}
		}
	}
	if content_length > MAX_BODY_BYTES {
		return {}, .Body_Too_Large
	}

	body_start := header_end + 4
	total := body_start + content_length
	if len(buf) < total {
		reserve(&buf, total)
		for len(buf) < total {
			n, rerr := net.recv_tcp(sock, chunk[:min(len(chunk), total - len(buf))])
			if rerr != nil || n == 0 {
				return {}, .Closed
			}
			append(&buf, ..chunk[:n])
		}
	}
	req.body = buf[body_start:total]
	return req, .None
}

status_text :: proc(status: int) -> string {
	switch status {
	case 200: return "OK"
	case 201: return "Created"
	case 204: return "No Content"
	case 400: return "Bad Request"
	case 404: return "Not Found"
	case 405: return "Method Not Allowed"
	case 413: return "Payload Too Large"
	case 431: return "Request Header Fields Too Large"
	case 500: return "Internal Server Error"
	case 501: return "Not Implemented"
	}
	return "Unknown"
}

write_response :: proc(sock: net.TCP_Socket, res: Response) {
	b := strings.builder_make(0, 256, context.temp_allocator)
	strings.write_string(&b, "HTTP/1.1 ")
	strings.write_int(&b, res.status)
	strings.write_byte(&b, ' ')
	strings.write_string(&b, status_text(res.status))
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
	// 204 must not carry a body; every other status gets an explicit length.
	if res.status != 204 {
		strings.write_string(&b, "Content-Length: ")
		strings.write_int(&b, len(res.body))
		strings.write_string(&b, "\r\n")
	}
	strings.write_string(&b, "\r\n")

	if len(res.body) > 0 && len(res.body) <= 16 * 1024 {
		// Small bodies go out in a single write.
		strings.write_bytes(&b, res.body)
		_, _ = net.send_tcp(sock, b.buf[:])
		return
	}
	if _, err := net.send_tcp(sock, b.buf[:]); err != nil {
		return
	}
	if len(res.body) > 0 {
		_, _ = net.send_tcp(sock, res.body)
	}
}
