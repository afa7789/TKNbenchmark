//! `PUT /notes/{id}` and `DELETE /notes/{id}`.

const std = @import("std");
const api = @import("../api.zig");
const note = @import("../note.zig");
const store = @import("../store/crud.zig");
const Response = api.Response;

/// Replaces the note: an omitted `body` or `tags` becomes `""` or `[]`.
/// 200 with the updated note, 400 on invalid input, 404 if there is no note.
pub fn update(ctx: *const api.Context, id: i64, req: api.Request) !Response {
    const input = note.parseInput(ctx.arena, req.body) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |e| return Response.badRequest(ctx.arena, note.errorMessage(e)),
    };

    const conn = try ctx.acquireDb();
    defer ctx.releaseDb(conn);
    const updated = try store.update(conn, id, input) orelse return Response.notFound(ctx.arena);
    return Response.json(ctx.arena, .ok, updated);
}

/// 204 with an empty body, 404 if there is no note.
pub fn delete(ctx: *const api.Context, id: i64) !Response {
    const conn = try ctx.acquireDb();
    defer ctx.releaseDb(conn);
    if (!try store.delete(conn, id)) return Response.notFound(ctx.arena);
    return Response.empty(.no_content);
}

const testing = std.testing;
const TestEnv = @import("../TestEnv.zig");

test "update replaces the note" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.POST, "/notes",
        \\{"title":"old","body":"text","tags":["x"]}
    , .created, null);
    try env.expect(.PUT, "/notes/1",
        \\{"title":"  new  ","tags":["b","a","b"]}
    , .ok,
        \\{"id":1,"title":"new","body":"","tags":["a","b"]}
    );
    try env.expect(.GET, "/notes/1", "", .ok,
        \\{"id":1,"title":"new","body":"","tags":["a","b"]}
    );
}

test "update rejects invalid input and unknown notes" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.POST, "/notes", "{\"title\":\"keep\",\"tags\":[\"t\"]}", .created, null);
    try env.expect(.PUT, "/notes/9", "{\"title\":\"none\"}", .not_found, null);
    try env.expect(.PUT, "/notes/1", "{\"title\":\"\"}", .bad_request,
        \\{"error":"title must be a string of 1 to 200 characters"}
    );
    try env.expect(.PUT, "/notes/1", "not json", .bad_request, null);
    try env.expect(.PUT, "/notes/1", "[]", .bad_request, null);
    try env.expect(.PUT, "/notes/1", "{\"title\":\"x\",\"body\":1}", .bad_request, null);
    try env.expect(.PUT, "/notes/1", "{\"title\":\"x\",\"tags\":[\"A\"]}", .bad_request, null);
    // The note is untouched.
    try env.expect(.GET, "/notes/1", "", .ok,
        \\{"id":1,"title":"keep","body":"","tags":["t"]}
    );
}

test "delete" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.POST, "/notes", "{\"title\":\"a\"}", .created, null);
    try env.expect(.POST, "/notes", "{\"title\":\"b\"}", .created, null);

    const res = try env.request(.DELETE, "/notes/1", "");
    try testing.expectEqual(.no_content, res.status);
    try testing.expectEqualStrings("", res.body);

    try env.expect(.GET, "/notes/1", "", .not_found, null);
    try env.expect(.DELETE, "/notes/1", "", .not_found, null);
    try env.expect(.PUT, "/notes/1", "{\"title\":\"x\"}", .not_found, null);
    // Ids are never reused.
    try env.expect(.POST, "/notes", "{\"title\":\"c\"}", .created,
        \\{"id":3,"title":"c","body":"","tags":[]}
    );
}
