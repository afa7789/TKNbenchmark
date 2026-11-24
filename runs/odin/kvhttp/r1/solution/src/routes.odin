package kvhttp

import "core:strings"

KV_PREFIX :: "/kv/"
MAX_KEY_LEN :: 64

handle :: proc(store: ^Store, req: Request) -> Response {
	switch {
	case req.path == "/health":
		if req.method != "GET" {
			return {status = 405}
		}
		return {status = 200, content_type = "text/plain", body = transmute([]byte)string("ok")}

	case req.path == "/kv":
		if req.method != "GET" {
			return {status = 405}
		}
		return {status = 200, content_type = "application/json", body = keys_json(store)}

	case strings.has_prefix(req.path, KV_PREFIX):
		key := req.path[len(KV_PREFIX):]
		if !valid_key(key) {
			return {status = 400}
		}
		switch req.method {
		case "GET":
			value, found := store_get(store, key)
			if !found {
				return {status = 404}
			}
			return {status = 200, content_type = "application/octet-stream", body = value}
		case "PUT":
			created := store_put(store, key, req.body)
			return {status = created ? 201 : 200}
		case "DELETE":
			return {status = store_delete(store, key) ? 204 : 404}
		}
		return {status = 405}
	}
	return {status = 404}
}

valid_key :: proc(key: string) -> bool {
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

// keys_json renders the sorted key list as a JSON array. Valid keys never
// contain characters that need escaping.
@(private = "file")
keys_json :: proc(store: ^Store) -> []byte {
	keys := store_keys(store)
	sb := strings.builder_make()
	strings.write_byte(&sb, '[')
	for key, i in keys {
		if i > 0 {
			strings.write_byte(&sb, ',')
		}
		strings.write_byte(&sb, '"')
		strings.write_string(&sb, key)
		strings.write_byte(&sb, '"')
	}
	strings.write_byte(&sb, ']')
	return sb.buf[:]
}
