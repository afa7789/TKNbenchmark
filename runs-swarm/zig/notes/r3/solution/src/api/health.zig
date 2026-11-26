//! GET /health: liveness probe.

const Context = @import("../http/Context.zig");

pub fn get(ctx: *Context) Context.Error!void {
    try ctx.send(.ok, "text/plain", "ok");
}
