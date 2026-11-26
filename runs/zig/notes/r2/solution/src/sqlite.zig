//! A thin, typed wrapper over the parts of the SQLite C API this service uses.

const std = @import("std");
const c = @import("c");

const log = std.log.scoped(.sqlite);

pub const Error = error{SqliteError};

pub const Db = struct {
    handle: *c.sqlite3,

    pub fn open(path: [:0]const u8) Error!Db {
        var handle: ?*c.sqlite3 = null;
        const flags = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX;
        const rc = c.sqlite3_open_v2(path.ptr, &handle, flags, null);
        if (rc != c.SQLITE_OK) {
            if (handle) |h| {
                log.err("cannot open {s}: {s}", .{ path, c.sqlite3_errmsg(h) });
                _ = c.sqlite3_close(h);
            } else {
                log.err("cannot open {s}: {s}", .{ path, c.sqlite3_errstr(rc) });
            }
            return error.SqliteError;
        }
        const db: Db = .{ .handle = handle.? };
        _ = c.sqlite3_extended_result_codes(db.handle, 1);
        return db;
    }

    pub fn close(db: Db) void {
        _ = c.sqlite3_close_v2(db.handle);
    }

    /// Runs one or more SQL statements that take no parameters and return no rows.
    pub fn exec(db: Db, sql: [:0]const u8) Error!void {
        var msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(db.handle, sql.ptr, null, null, &msg);
        if (rc != c.SQLITE_OK) {
            log.err("exec failed: {s}", .{if (msg != null) std.mem.span(msg) else "unknown error"});
            c.sqlite3_free(msg);
            return error.SqliteError;
        }
    }

    pub fn prepare(db: Db, sql: []const u8) Error!Statement {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(db.handle, sql.ptr, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return db.fail("prepare");
        return .{ .db = db, .handle = stmt.? };
    }

    pub fn setBusyTimeout(db: Db, ms: c_int) void {
        _ = c.sqlite3_busy_timeout(db.handle, ms);
    }

    pub fn lastInsertRowId(db: Db) i64 {
        return c.sqlite3_last_insert_rowid(db.handle);
    }

    /// Number of rows modified by the most recent INSERT, UPDATE or DELETE.
    pub fn changes(db: Db) i64 {
        return c.sqlite3_changes64(db.handle);
    }

    /// Registers a deterministic scalar SQL function implemented in Zig.
    pub fn createScalarFunction(
        db: Db,
        name: [:0]const u8,
        n_args: c_int,
        func: *const fn (?*c.sqlite3_context, c_int, [*c]?*c.sqlite3_value) callconv(.c) void,
    ) Error!void {
        const rc = c.sqlite3_create_function_v2(
            db.handle,
            name.ptr,
            n_args,
            c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC | c.SQLITE_INNOCUOUS,
            null,
            func,
            null,
            null,
            null,
        );
        if (rc != c.SQLITE_OK) return db.fail("create function");
    }

    fn fail(db: Db, what: []const u8) Error {
        log.err("{s} failed: {s}", .{ what, c.sqlite3_errmsg(db.handle) });
        return error.SqliteError;
    }
};

pub const Statement = struct {
    db: Db,
    handle: *c.sqlite3_stmt,

    pub fn deinit(stmt: Statement) void {
        _ = c.sqlite3_finalize(stmt.handle);
    }

    /// Resets the statement so it can be stepped again with new bindings.
    pub fn reset(stmt: Statement) void {
        _ = c.sqlite3_reset(stmt.handle);
        _ = c.sqlite3_clear_bindings(stmt.handle);
    }

    /// Binds `value` to the 1-based parameter `index`. Text is bound without
    /// copying, so it must outlive the execution of the statement.
    pub fn bind(stmt: Statement, index: c_int, value: anytype) Error!void {
        const T = @TypeOf(value);
        const rc = switch (@typeInfo(T)) {
            .int, .comptime_int => c.sqlite3_bind_int64(stmt.handle, index, @intCast(value)),
            .null => c.sqlite3_bind_null(stmt.handle, index),
            .optional => if (value) |v| return stmt.bind(index, v) else c.sqlite3_bind_null(stmt.handle, index),
            else => blk: {
                const text: []const u8 = value;
                break :blk c.sqlite3_bind_text64(stmt.handle, index, text.ptr, text.len, c.SQLITE_STATIC, c.SQLITE_UTF8);
            },
        };
        if (rc != c.SQLITE_OK) return stmt.db.fail("bind");
    }

    /// Binds each element of the tuple `values` to consecutive parameters.
    pub fn bindAll(stmt: Statement, values: anytype) Error!void {
        inline for (values, 1..) |value, i| try stmt.bind(@intCast(i), value);
    }

    /// Advances to the next row. Returns false when the statement is done.
    pub fn step(stmt: Statement) Error!bool {
        return switch (c.sqlite3_step(stmt.handle)) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => stmt.db.fail("step"),
        };
    }

    /// Steps a statement that is expected to produce no rows.
    pub fn run(stmt: Statement) Error!void {
        while (try stmt.step()) {}
    }

    pub fn columnInt(stmt: Statement, col: c_int) i64 {
        return c.sqlite3_column_int64(stmt.handle, col);
    }

    /// Returns the text of a column. Valid until the next step, reset or deinit.
    pub fn columnText(stmt: Statement, col: c_int) []const u8 {
        const ptr = c.sqlite3_column_text(stmt.handle, col);
        const len: usize = @intCast(c.sqlite3_column_bytes(stmt.handle, col));
        if (ptr == null) return "";
        return ptr[0..len];
    }
};

/// Returns the bytes of a text argument passed to a SQL function.
pub fn valueText(value: ?*c.sqlite3_value) ?[]const u8 {
    const ptr = c.sqlite3_value_text(value) orelse return null;
    const len: usize = @intCast(c.sqlite3_value_bytes(value));
    return ptr[0..len];
}

pub fn resultBool(ctx: ?*c.sqlite3_context, value: bool) void {
    c.sqlite3_result_int(ctx, @intFromBool(value));
}

pub fn resultNull(ctx: ?*c.sqlite3_context) void {
    c.sqlite3_result_null(ctx);
}

test "prepare, bind and read back" {
    const db: Db = try .open(":memory:");
    defer db.close();
    try db.exec("CREATE TABLE t (n INTEGER, s TEXT)");

    const insert = try db.prepare("INSERT INTO t (n, s) VALUES (?, ?)");
    defer insert.deinit();
    try insert.bindAll(.{ 7, "seven" });
    try insert.run();
    insert.reset();
    try insert.bindAll(.{ 8, @as(?[]const u8, null) });
    try insert.run();

    const select = try db.prepare("SELECT n, s FROM t ORDER BY n");
    defer select.deinit();
    try std.testing.expect(try select.step());
    try std.testing.expectEqual(7, select.columnInt(0));
    try std.testing.expectEqualStrings("seven", select.columnText(1));
    try std.testing.expect(try select.step());
    try std.testing.expectEqualStrings("", select.columnText(1));
    try std.testing.expect(!try select.step());
}
