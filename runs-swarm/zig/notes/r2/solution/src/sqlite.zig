//! A thin, typed wrapper over the SQLite C API.
//!
//! A `Db` is a single connection. It must not be used from two threads at the
//! same time; `Store` serializes access to it.

const std = @import("std");
const c = @import("sqlite_c");

const log = std.log.scoped(.sqlite);

pub const Error = error{SqliteError};

pub const Db = struct {
    handle: *c.sqlite3,

    pub const OpenOptions = struct {
        /// Milliseconds to wait for a lock held by another connection.
        busy_timeout_ms: c_int = 5000,
    };

    /// Opens (creating it if needed) the database file at `path`.
    pub fn open(path: [:0]const u8, options: OpenOptions) Error!Db {
        var handle: ?*c.sqlite3 = null;
        const flags = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_EXRESCODE;
        const rc = c.sqlite3_open_v2(path.ptr, &handle, flags, null);
        if (rc != c.SQLITE_OK) {
            if (handle) |h| {
                log.err("open {s}: {s}", .{ path, std.mem.span(c.sqlite3_errmsg(h)) });
                _ = c.sqlite3_close_v2(h);
            } else {
                log.err("open {s}: {s}", .{ path, std.mem.span(c.sqlite3_errstr(rc)) });
            }
            return error.SqliteError;
        }
        const db: Db = .{ .handle = handle.? };
        _ = c.sqlite3_busy_timeout(db.handle, options.busy_timeout_ms);
        return db;
    }

    pub fn close(db: Db) void {
        _ = c.sqlite3_close_v2(db.handle);
    }

    /// Runs one or more SQL statements that take no parameters and return no rows.
    pub fn exec(db: Db, sql: [:0]const u8) Error!void {
        var message: [*c]u8 = null;
        const rc = c.sqlite3_exec(db.handle, sql.ptr, null, null, &message);
        if (rc != c.SQLITE_OK) {
            defer c.sqlite3_free(message);
            log.err("exec: {s}", .{if (message) |m| std.mem.span(m) else "unknown error"});
            return error.SqliteError;
        }
    }

    /// Compiles `sql` into a statement. The caller must `finalize` it.
    pub fn prepare(db: Db, sql: []const u8) Error!Statement {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(db.handle, sql.ptr, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return db.fail("prepare", rc);
        return .{ .db = db, .handle = stmt.? };
    }

    /// Prepares `sql`, binds `args` (a tuple) and runs it to completion.
    pub fn run(db: Db, sql: []const u8, args: anytype) Error!void {
        var stmt = try db.prepare(sql);
        defer stmt.finalize();
        try stmt.bindAll(args);
        while (try stmt.step()) {}
    }

    pub fn lastInsertRowId(db: Db) i64 {
        return c.sqlite3_last_insert_rowid(db.handle);
    }

    /// Rows modified by the most recent INSERT, UPDATE or DELETE.
    pub fn changes(db: Db) i64 {
        return c.sqlite3_changes64(db.handle);
    }

    pub fn errmsg(db: Db) []const u8 {
        return std.mem.span(c.sqlite3_errmsg(db.handle));
    }

    fn fail(db: Db, what: []const u8, rc: c_int) Error {
        log.err("{s}: {s} ({d})", .{ what, db.errmsg(), rc });
        return error.SqliteError;
    }

    /// Runs `func(db, args...)` inside a transaction: committed if it
    /// returns normally, rolled back if it returns an error.
    pub fn transaction(
        db: Db,
        comptime func: anytype,
        args: anytype,
    ) @typeInfo(@TypeOf(func)).@"fn".return_type.? {
        try db.exec("BEGIN IMMEDIATE");
        errdefer db.exec("ROLLBACK") catch {};
        const result = try @call(.auto, func, .{db} ++ args);
        try db.exec("COMMIT");
        return result;
    }
};

pub const Statement = struct {
    db: Db,
    handle: *c.sqlite3_stmt,

    pub fn finalize(stmt: Statement) void {
        _ = c.sqlite3_finalize(stmt.handle);
    }

    /// Clears bindings and rewinds the statement so it can run again.
    pub fn reset(stmt: Statement) void {
        _ = c.sqlite3_reset(stmt.handle);
        _ = c.sqlite3_clear_bindings(stmt.handle);
    }

    /// Binds `value` to the 1-based parameter `index`. Text and blobs are
    /// bound without copying: they must outlive the statement's execution.
    pub fn bind(stmt: Statement, index: c_int, value: anytype) Error!void {
        const T = @TypeOf(value);
        const rc = switch (@typeInfo(T)) {
            .int, .comptime_int => c.sqlite3_bind_int64(stmt.handle, index, @intCast(value)),
            .float, .comptime_float => c.sqlite3_bind_double(stmt.handle, index, value),
            .bool => c.sqlite3_bind_int(stmt.handle, index, @intFromBool(value)),
            .null => c.sqlite3_bind_null(stmt.handle, index),
            .optional => if (value) |v| return stmt.bind(index, v) else c.sqlite3_bind_null(stmt.handle, index),
            else => blk: {
                const bytes: []const u8 = value;
                break :blk c.sqlite3_bind_text64(stmt.handle, index, bytes.ptr, bytes.len, null, c.SQLITE_UTF8);
            },
        };
        if (rc != c.SQLITE_OK) return stmt.db.fail("bind", rc);
    }

    /// Binds the fields of the tuple `args` to parameters 1, 2, ….
    pub fn bindAll(stmt: Statement, args: anytype) Error!void {
        inline for (args, 1..) |arg, index| try stmt.bind(index, arg);
    }

    /// Advances to the next row: true if a row is available, false when done.
    pub fn step(stmt: Statement) Error!bool {
        return switch (c.sqlite3_step(stmt.handle)) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => |rc| stmt.db.fail("step", rc),
        };
    }

    pub fn int(stmt: Statement, column: c_int) i64 {
        return c.sqlite3_column_int64(stmt.handle, column);
    }

    /// The column as text. Only valid until the next `step`, `reset` or
    /// `finalize`; use `textAlloc` to keep it.
    pub fn text(stmt: Statement, column: c_int) []const u8 {
        const ptr = c.sqlite3_column_text(stmt.handle, column) orelse return "";
        const len: usize = @intCast(c.sqlite3_column_bytes(stmt.handle, column));
        return ptr[0..len];
    }

    pub fn textAlloc(stmt: Statement, gpa: std.mem.Allocator, column: c_int) error{OutOfMemory}![]u8 {
        return gpa.dupe(u8, stmt.text(column));
    }
};

test "exec, bind, step and read columns" {
    const db = try Db.open(":memory:", .{});
    defer db.close();

    try db.exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
    try db.run("INSERT INTO t (name) VALUES (?1)", .{"alpha"});
    try std.testing.expectEqual(@as(i64, 1), db.lastInsertRowId());
    try db.run("INSERT INTO t (name) VALUES (?1)", .{"beta"});

    const stmt = try db.prepare("SELECT id, name FROM t WHERE id >= ?1 ORDER BY id");
    defer stmt.finalize();
    try stmt.bindAll(.{2});
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(@as(i64, 2), stmt.int(0));
    try std.testing.expectEqualStrings("beta", stmt.text(1));
    try std.testing.expect(!try stmt.step());
}

test "transaction rolls back on error" {
    const db = try Db.open(":memory:", .{});
    defer db.close();
    try db.exec("CREATE TABLE t (v INTEGER)");

    const insertThenFail = struct {
        fn f(d: Db, v: i64) !void {
            try d.run("INSERT INTO t (v) VALUES (?1)", .{v});
            return error.Boom;
        }
    }.f;
    try std.testing.expectError(error.Boom, db.transaction(insertThenFail, .{@as(i64, 7)}));

    const stmt = try db.prepare("SELECT count(*) FROM t");
    defer stmt.finalize();
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(@as(i64, 0), stmt.int(0));
}
