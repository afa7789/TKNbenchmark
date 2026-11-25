package main

import "core:strings"

MAX_KEY_LEN :: 64

// handle_request maps a parsed request to a response. Response memory is
// allocated with `allocator`.
handle_request :: proc(store: ^Store, req: Request, allocator := context.allocator) -> Response {
	switch {
	case req.path == "/health":
		if req.method != "GET" {
			return {status = .Method_Not_Allowed}
		}
		return {status = .OK, content_type = "text/plain", body = transmute([]byte)string("ok")}

	case req.path == "/kv":
		if req.method != "GET" {
			return {status = .Method_Not_Allowed}
		}
		return {status = .OK, content_type = "application/json", body = keys_json(store, allocator)}

	case strings.has_prefix(req.path, "/kv/"):
		key := req.path[len("/kv/"):]
		if !is_valid_key(key) {
			return {status = .Bad_Request}
		}
		switch req.method {
		case "GET":
			value, found := store_get(store, key, allocator)
			if !found {
				return {status = .Not_Found}
			}
			return {status = .OK, content_type = "application/octet-stream", body = value}
		case "PUT":
			return {status = store_put(store, key, req.body) ? .Created : .OK}
		case "DELETE":
			return {status = store_delete(store, key) ? .No_Content : .Not_Found}
		case:
			return {status = .Method_Not_Allowed}
		}
	}
	return {status = .Not_Found}
}

// is_valid_key reports whether key matches [A-Za-z0-9_-]{1,64}.
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

// keys_json renders every key as a sorted JSON array. Keys are restricted to
// characters that never need escaping.
keys_json :: proc(store: ^Store, allocator := context.allocator) -> []byte {
	keys := store_keys(store, allocator)
	defer {
		for k in keys {
			delete(k, allocator)
		}
		delete(keys, allocator)
	}

	size := 2
	for k in keys {
		size += len(k) + 3
	}
	b := strings.builder_make(0, size, allocator)
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
	return b.buf[:]
}
