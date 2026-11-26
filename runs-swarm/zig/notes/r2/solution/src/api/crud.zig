//! `PUT /notes/{id}` and `DELETE /notes/{id}`.
//!
//! Data access is in `store/crud.zig`; input validation is shared with
//! `POST /notes` (`model.parseNoteInput`).

const web = @import("../web.zig");
const model = @import("../model.zig");
const store = @import("../store/crud.zig");

/// `PUT /notes/{id}` with `{title, body?, tags?}` (full replacement):
/// 200 and the updated note, 400 or 404.
pub fn update(req: *web.Request, id: i64) !web.Response {
    var diag: model.Diagnostic = .{};
    const input = model.parseNoteInput(req.arena, req.body, &diag) catch |err| switch (err) {
        error.InvalidInput => return web.jsonError(req.arena, .bad_request, diag.message),
        else => |e| return e,
    };
    const note = try store.update(req.store, id, input) orelse
        return web.jsonError(req.arena, .not_found, "note not found");
    return web.json(req.arena, .ok, note);
}

/// `DELETE /notes/{id}`: 204 with an empty body, or 404.
pub fn remove(req: *web.Request, id: i64) !web.Response {
    if (!try store.remove(req.store, id)) return web.jsonError(req.arena, .not_found, "note not found");
    return web.no_content;
}
