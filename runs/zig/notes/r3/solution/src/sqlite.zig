//! Thin, typed wrapper around the parts of the SQLite C API this service uses.

const std = @import("std");

pub const c = @cImport(@cInclude("sqlite3.h"));

pub const Error = error{Sqlite};

fn check(db: ?*c.sqlite3, rc: c_int) Error!void {
    if (rc == c.SQLITE_OK or rc == c.SQLITE_DONE or rc == c.SQLITE_ROW) return;
    std.log.err("sqlite error {d}: {s}", .{ rc, std.mem.span(c.sqlite3_errmsg(db)) });
    return error.Sqlite;
}

pub const Db = struct {
    handle: *c.sqlite3,

    pub fn open(path: [:0]const u8) Error!Db {
        var handle: ?*c.sqlite3 = null;
        const flags = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX;
        const rc = c.sqlite3_open_v2(path.ptr, &handle, flags, null);
        if (rc != c.SQLITE_OK) {
            std.log.err("cannot open database '{s}': {s}", .{ path, c.sqlite3_errstr(rc) });
            if (handle) |h| _ = c.sqlite3_close(h);
            return error.Sqlite;
        }
        return .{ .handle = handle.? };
    }

    pub fn close(db: Db) void {
        _ = c.sqlite3_close(db.handle);
    }

    /// Runs one or more SQL statements that take no parameters and return no rows.
    pub fn exec(db: Db, sql: [:0]const u8) Error!void {
        try check(db.handle, c.sqlite3_exec(db.handle, sql.ptr, null, null, null));
    }

    pub fn prepare(db: Db, sql: []const u8) Error!Stmt {
        var stmt: ?*c.sqlite3_stmt = null;
        try check(db.handle, c.sqlite3_prepare_v2(db.handle, sql.ptr, @intCast(sql.len), &stmt, null));
        return .{ .handle = stmt.?, .db = db.handle };
    }

    /// Number of rows modified by the most recent INSERT, UPDATE or DELETE.
    pub fn changes(db: Db) i64 {
        return c.sqlite3_changes64(db.handle);
    }

    pub fn lastInsertRowId(db: Db) i64 {
        return c.sqlite3_last_insert_rowid(db.handle);
    }
};

pub const Stmt = struct {
    handle: *c.sqlite3_stmt,
    db: *c.sqlite3,

    pub fn finalize(s: Stmt) void {
        _ = c.sqlite3_finalize(s.handle);
    }

    pub fn reset(s: Stmt) Error!void {
        try check(s.db, c.sqlite3_reset(s.handle));
        try check(s.db, c.sqlite3_clear_bindings(s.handle));
    }

    /// Binds `value` to the 1-based parameter `index`. Text is bound without a
    /// copy, so it must outlive the next `step`/`reset`.
    pub fn bind(s: Stmt, index: c_int, value: anytype) Error!void {
        const T = @TypeOf(value);
        const rc = switch (@typeInfo(T)) {
            .int, .comptime_int => c.sqlite3_bind_int64(s.handle, index, @intCast(value)),
            .pointer => blk: {
                const bytes: []const u8 = value;
                break :blk c.sqlite3_bind_text64(s.handle, index, bytes.ptr, bytes.len, null, c.SQLITE_UTF8);
            },
            else => @compileError("unsupported bind type " ++ @typeName(T)),
        };
        try check(s.db, rc);
    }

    /// Binds each element of the tuple `values` to parameters 1, 2, ….
    pub fn bindAll(s: Stmt, values: anytype) Error!void {
        inline for (values, 1..) |v, i| try s.bind(@intCast(i), v);
    }

    /// Advances the statement; returns true when a row is available.
    pub fn step(s: Stmt) Error!bool {
        const rc = c.sqlite3_step(s.handle);
        try check(s.db, rc);
        return rc == c.SQLITE_ROW;
    }

    pub fn int(s: Stmt, col: c_int) i64 {
        return c.sqlite3_column_int64(s.handle, col);
    }

    /// Text of column `col`, valid until the next `step`, `reset` or `finalize`.
    pub fn text(s: Stmt, col: c_int) []const u8 {
        const ptr = c.sqlite3_column_text(s.handle, col) orelse return "";
        const len: usize = @intCast(c.sqlite3_column_bytes(s.handle, col));
        return ptr[0..len];
    }
};

test "open in-memory database and round-trip a row" {
    const db = try Db.open(":memory:");
    defer db.close();
    try db.exec("CREATE TABLE t (a INTEGER, b TEXT)");
    {
        const ins = try db.prepare("INSERT INTO t VALUES (?, ?)");
        defer ins.finalize();
        try ins.bindAll(.{ 42, "hi" });
        try std.testing.expect(!try ins.step());
    }
    const sel = try db.prepare("SELECT a, b FROM t");
    defer sel.finalize();
    try std.testing.expect(try sel.step());
    try std.testing.expectEqual(42, sel.int(0));
    try std.testing.expectEqualStrings("hi", sel.text(1));
    try std.testing.expect(!try sel.step());
}
