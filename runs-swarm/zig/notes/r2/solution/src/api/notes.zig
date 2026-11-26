//! `POST /notes` and `GET /notes/{id}`.

const std = @import("std");
const web = @import("../web.zig");
const model = @import("../model.zig");
const store = @import("../store/notes.zig");

/// `POST /notes` with `{title, body?, tags?}`: 201 and the created note.
pub fn create(req: *web.Request) !web.Response {
    var diag: model.Diagnostic = .{};
    const input = model.parseNoteInput(req.arena, req.body, &diag) catch |err| switch (err) {
        error.InvalidInput => return web.jsonError(req.arena, .bad_request, diag.message),
        else => |e| return e,
    };
    const note = try store.create(req.store, input);
    return web.json(req.arena, .created, note);
}

/// `GET /notes/{id}`: 200 and the note, or 404.
pub fn show(req: *web.Request, id: i64) !web.Response {
    const note = try store.get(req.store, req.arena, id) orelse
        return web.jsonError(req.arena, .not_found, "note not found");
    return web.json(req.arena, .ok, note);
}
