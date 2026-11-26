//! `POST /notes` and `GET /notes/{id}`.

const std = @import("std");
const api = @import("../api.zig");
const note = @import("../note.zig");
const store = @import("../store/notes.zig");
const Response = api.Response;

pub fn create(ctx: *const api.Context, req: api.Request) !Response {
    const input = note.parseInput(ctx.arena, req.body) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |e| return Response.badRequest(ctx.arena, note.errorMessage(e)),
    };

    const conn = try ctx.acquireDb();
    defer ctx.releaseDb(conn);
    const created = try store.create(conn, input);
    return Response.json(ctx.arena, .created, created);
}

pub fn get(ctx: *const api.Context, id: i64) !Response {
    const conn = try ctx.acquireDb();
    defer ctx.releaseDb(conn);
    const found = try store.get(conn, ctx.arena, id) orelse return Response.notFound(ctx.arena);
    return Response.json(ctx.arena, .ok, found);
}

const testing = std.testing;
const TestEnv = @import("../TestEnv.zig");

test "create then get" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.POST, "/notes",
        \\{"title":"  second  ","body":"some text","tags":["work","b-2","work"]}
    , .created,
        \\{"id":1,"title":"second","body":"some text","tags":["b-2","work"]}
    );
    try env.expect(.GET, "/notes/1", "", .ok,
        \\{"id":1,"title":"second","body":"some text","tags":["b-2","work"]}
    );
}

test "create rejects invalid notes" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.POST, "/notes", "{\"title\": ", .bad_request,
        \\{"error":"request body is not valid JSON"}
    );
    try env.expect(.POST, "/notes", "{\"title\":\"x\",\"tags\":[\"Bad\"]}", .bad_request, null);
    // Nothing was stored.
    try env.expect(.GET, "/notes/1", "", .not_found, null);
}
