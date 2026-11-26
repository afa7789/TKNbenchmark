//! `GET /health`: liveness probe.

const web = @import("../web.zig");

pub fn get(req: *web.Request) !web.Response {
    _ = req;
    return web.text(.ok, "ok");
}
