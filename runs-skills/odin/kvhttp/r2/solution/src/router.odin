package main

import "core:strings"

KV_PREFIX :: "/kv/"
MAX_KEY_LEN :: 64

is_valid_key :: proc(key: string) -> bool {
	if len(key) == 0 || len(key) > MAX_KEY_LEN {
		return false
	}
	for i in 0 ..< len(key) {
		switch key[i] {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '_', '-':
		case:
			return false
		}
	}
	return true
}

text :: proc(status: Status, body := "") -> Response {
	return {status = status, content_type = "text/plain; charset=utf-8" if body != "" else "", body = transmute([]byte)body}
}

method_not_allowed :: proc(allow: string) -> Response {
	return {status = .Method_Not_Allowed, allow = allow}
}

// handle maps a request to a response. Response memory comes from context.allocator.
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
		return list_keys(store)

	case strings.has_prefix(req.path, KV_PREFIX):
		key := req.path[len(KV_PREFIX):]
		if !is_valid_key(key) {
			return {status = .Bad_Request}
		}
		switch req.method {
		case "GET":
			value, found := store_get(store, key)
			if !found {
				return {status = .Not_Found}
			}
			return {status = .OK, content_type = "application/octet-stream", body = value}
		case "PUT":
			created := store_put(store, key, req.body)
			return {status = .Created if created else .OK}
		case "DELETE":
			if !store_delete(store, key) {
				return {status = .Not_Found}
			}
			return {status = .No_Content}
		case:
			return method_not_allowed("GET, PUT, DELETE")
		}
	}
	return {status = .Not_Found}
}

list_keys :: proc(store: ^Store) -> Response {
	keys := store_keys(store)

	// Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
	b := strings.builder_make()
	strings.write_byte(&b, '[')
	for k, i in keys {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_byte(&b, '"')
		strings.write_string(&b, k)
		strings.write_byte(&b, '"')
	}
	strings.write_byte(&b, ']')
	return {status = .OK, content_type = "application/json", body = b.buf[:]}
}
