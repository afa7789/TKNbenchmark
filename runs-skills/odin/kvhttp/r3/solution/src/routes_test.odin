package main

import "core:testing"

@(test)
test_is_valid_key :: proc(t: ^testing.T) {
	testing.expect(t, is_valid_key("a"))
	testing.expect(t, is_valid_key("Az09_-"))
	testing.expect(t, is_valid_key("k123456789012345678901234567890123456789012345678901234567890123"))
	testing.expect(t, !is_valid_key(""))
	testing.expect(t, !is_valid_key("k1234567890123456789012345678901234567890123456789012345678901234"))
	testing.expect(t, !is_valid_key("a/b"))
	testing.expect(t, !is_valid_key("a.b"))
	testing.expect(t, !is_valid_key("é"))
}

@(test)
test_routes :: proc(t: ^testing.T) {
	store: Store
	store_init(&store)
	defer store_destroy(&store)
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)

	status :: proc(s: ^Store, method, path: string, body := "") -> Status {
		return handle_request(s, {method = method, path = path, body = transmute([]byte)body}).status
	}

	testing.expect_value(t, status(&store, "GET", "/health"), Status.OK)
	testing.expect_value(t, status(&store, "POST", "/health"), Status.Method_Not_Allowed)
	testing.expect_value(t, status(&store, "PUT", "/kv/b", "2"), Status.Created)
	testing.expect_value(t, status(&store, "PUT", "/kv/a", "1"), Status.Created)
	testing.expect_value(t, status(&store, "PUT", "/kv/a", "3"), Status.OK)
	testing.expect_value(t, status(&store, "PATCH", "/kv/a"), Status.Method_Not_Allowed)
	testing.expect_value(t, status(&store, "GET", "/kv/a.b"), Status.Bad_Request)
	testing.expect_value(t, status(&store, "GET", "/nope"), Status.Not_Found)

	res := handle_request(&store, {method = "GET", path = "/kv/a"})
	testing.expect_value(t, string(res.body), "3")

	res = handle_request(&store, {method = "GET", path = "/kv"})
	testing.expect_value(t, string(res.body), `["a","b"]`)
	testing.expect_value(t, res.content_type, "application/json")

	testing.expect_value(t, status(&store, "DELETE", "/kv/a"), Status.No_Content)
	testing.expect_value(t, status(&store, "DELETE", "/kv/a"), Status.Not_Found)
	testing.expect_value(t, status(&store, "GET", "/kv/a"), Status.Not_Found)
}
