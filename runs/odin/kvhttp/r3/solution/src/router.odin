package kvhttp

import "core:strings"

MAX_KEY_LEN :: 64

KV_PREFIX :: "/kv/"

// handle routes a request against the store. Response bodies are allocated with
// `context.temp_allocator`. Ownership of `req.body` passes to the store on a
// successful PUT; otherwise it remains with the caller (body_consumed = false).
handle :: proc(store: ^Store, req: Request) -> (res: Response, body_consumed: bool) {
	switch {
	case req.path == "/health":
		if req.method != "GET" {
			return method_not_allowed("GET"), false
		}
		return {status = .OK, content_type = "text/plain; charset=utf-8", body = transmute([]byte)string("ok")}, false

	case req.path == "/kv":
		if req.method != "GET" {
			return method_not_allowed("GET"), false
		}
		return list_keys(store), false

	case strings.has_prefix(req.path, KV_PREFIX):
		key := req.path[len(KV_PREFIX):]
		if !is_valid_key(key) {
			return {status = .Bad_Request}, false
		}
		switch req.method {
		case "GET":
			value, found := store_get(store, key, context.temp_allocator)
			if !found {
				return {status = .Not_Found}, false
			}
			return {status = .OK, content_type = "application/octet-stream", body = value}, false
		case "PUT":
			created, err := store_put(store, key, req.body)
			if err != nil {
				return {status = .Internal_Server_Error}, true
			}
			return {status = .Created if created else .OK}, true
		case "DELETE":
			if !store_delete(store, key) {
				return {status = .Not_Found}, false
			}
			return {status = .No_Content}, false
		case:
			return method_not_allowed("GET, PUT, DELETE"), false
		}
	}
	return {status = .Not_Found}, false
}

is_valid_key :: proc(key: string) -> bool {
	if len(key) < 1 || len(key) > MAX_KEY_LEN {
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

@(private = "file")
method_not_allowed :: proc(allow: string) -> Response {
	return {status = .Method_Not_Allowed, allow = allow}
}

@(private = "file")
list_keys :: proc(store: ^Store) -> Response {
	keys := store_keys(store, context.temp_allocator)

	// Keys are restricted to [A-Za-z0-9_-], so they never need JSON escaping.
	b := strings.builder_make(context.temp_allocator)
	strings.write_byte(&b, '[')
	for key, i in keys {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_byte(&b, '"')
		strings.write_string(&b, key)
		strings.write_byte(&b, '"')
	}
	strings.write_byte(&b, ']')

	return {status = .OK, content_type = "application/json", body = b.buf[:]}
}
