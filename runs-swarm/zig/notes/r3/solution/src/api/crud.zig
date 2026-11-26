//! PUT /notes/{id} and DELETE /notes/{id}.

const Context = @import("../http/Context.zig");
const notes = @import("notes.zig");
const crud_db = @import("../db/crud.zig");

/// PUT /notes/{id}: replaces the note; an omitted `body` or `tags` becomes
/// `""` or `[]`.
pub fn update(ctx: *Context) Context.Error!void {
    const id = try notes.idParam(ctx) orelse return;
    const input = try notes.readInput(ctx) orelse return;
    const updated = blk: {
        const db = ctx.store.acquire();
        defer ctx.store.release();
        break :blk try crud_db.update(db, id, input);
    };
    if (updated) |n| return ctx.sendJson(.ok, n);
    try notes.sendNotFound(ctx);
}

/// DELETE /notes/{id}
pub fn remove(ctx: *Context) Context.Error!void {
    const id = try notes.idParam(ctx) orelse return;
    const removed = blk: {
        const db = ctx.store.acquire();
        defer ctx.store.release();
        break :blk try crud_db.remove(db, id);
    };
    if (removed) return ctx.sendEmpty(.no_content);
    try notes.sendNotFound(ctx);
}

test {
    _ = crud_db;
}
