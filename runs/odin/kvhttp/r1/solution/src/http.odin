package kvhttp

import "core:bytes"
import "core:net"
import "core:strconv"
import "core:strings"

MAX_HEADER_BYTES :: 64 * 1024
MAX_BODY_BYTES :: 1024 * 1024

Request :: struct {
	method: string,
	path:   string,
	body:   []byte,
}

Parse_Error :: enum {
	None,
	Connection_Closed, // peer went away or timed out; nothing to reply to
	Malformed,         // 400
	Headers_Too_Large, // 431
	Body_Too_Large,    // 413
}

Response :: struct {
	status:       int,
	content_type: string,
	body:         []byte,
}

// read_request reads one HTTP/1.1 request from sock. All memory comes from
// context.allocator, which the caller is expected to scope to the connection.
read_request :: proc(sock: net.TCP_Socket) -> (req: Request, err: Parse_Error) {
	buf := make([dynamic]byte, 0, 4096)
	chunk: [4096]byte

	header_end := -1
	for header_end < 0 {
		n, recv_err := net.recv_tcp(sock, chunk[:])
		if recv_err != nil || n == 0 {
			return {}, .Connection_Closed
		}
		search_from := max(0, len(buf) - 3)
		append(&buf, ..chunk[:n])
		if i := bytes.index(buf[search_from:], {'\r', '\n', '\r', '\n'}); i >= 0 {
			header_end = search_from + i
		} else if len(buf) > MAX_HEADER_BYTES {
			return {}, .Headers_Too_Large
		}
	}

	head := string(buf[:header_end])
	request_line, _, header_block := strings_cut(head, "\r\n")

	method, _, rest := strings_cut(request_line, " ")
	target, _, version := strings_cut(rest, " ")
	if method == "" || target == "" || !strings.has_prefix(version, "HTTP/") {
		return {}, .Malformed
	}
	req.method = method
	req.path = target

	content_length := 0
	for line in strings.split_lines_iterator(&header_block) {
		name, found, value := strings_cut(line, ":")
		if !found {
			return {}, .Malformed
		}
		if strings.equal_fold(strings.trim_space(name), "Content-Length") {
			n, ok := strconv.parse_int(strings.trim_space(value), 10)
			if !ok || n < 0 {
				return {}, .Malformed
			}
			content_length = n
		}
	}

	if content_length > MAX_BODY_BYTES {
		return req, .Body_Too_Large
	}

	body_start := header_end + 4
	already := len(buf) - body_start
	if already >= content_length {
		req.body = buf[body_start:][:content_length]
		return req, .None
	}

	body := make([]byte, content_length)
	copy(body, buf[body_start:])
	for already < content_length {
		n, recv_err := net.recv_tcp(sock, body[already:])
		if recv_err != nil || n == 0 {
			return {}, .Connection_Closed
		}
		already += n
	}
	req.body = body
	return req, .None
}

write_response :: proc(sock: net.TCP_Socket, res: Response) -> net.TCP_Send_Error {
	sb := strings.builder_make(0, 256 + len(res.body))
	strings.write_string(&sb, "HTTP/1.1 ")
	strings.write_int(&sb, res.status)
	strings.write_byte(&sb, ' ')
	strings.write_string(&sb, status_text(res.status))
	// RFC 9110 §8.6: no Content-Length on 204; the connection closes after the head.
	if res.status != 204 {
		strings.write_string(&sb, "\r\nContent-Length: ")
		strings.write_int(&sb, len(res.body))
	}
	if res.content_type != "" {
		strings.write_string(&sb, "\r\nContent-Type: ")
		strings.write_string(&sb, res.content_type)
	}
	strings.write_string(&sb, "\r\nConnection: close\r\n\r\n")
	strings.write_bytes(&sb, res.body)

	_, err := net.send_tcp(sock, sb.buf[:])
	return err
}

status_text :: proc(status: int) -> string {
	switch status {
	case 200: return "OK"
	case 201: return "Created"
	case 204: return "No Content"
	case 400: return "Bad Request"
	case 404: return "Not Found"
	case 405: return "Method Not Allowed"
	case 413: return "Content Too Large"
	case 431: return "Request Header Fields Too Large"
	case 500: return "Internal Server Error"
	}
	return "Unknown"
}

@(private = "file")
strings_cut :: proc(s, sep: string) -> (before: string, found: bool, after: string) {
	if i := strings.index(s, sep); i >= 0 {
		return s[:i], true, s[i + len(sep):]
	}
	return s, false, ""
}
