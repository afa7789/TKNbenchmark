//! Thin, allocation-free wrapper over the SQLite C API.
//!
//! Only the parts of the API the service needs are exposed. Text and blob
//! values are bound with `SQLITE_STATIC`: bound slices must stay alive until
//! the statement is reset or finalized, which is always the case when a
//! statement is prepared, bound and stepped within one scope.

const std = @import("std");
const c = @import("sqlite_c");

const log = std.log.scoped(.sqlite);

pub const Error = error{
    Busy,
    Locked,
    Constraint,
    ReadOnly,
    DiskFull,
    CantOpen,
    Corrupt,
    IoFailure,
    Misuse,
    OutOfMemory,
    SqliteFailure,
};

fn check(rc: c_int) Error!void {
    if (rc == c.SQLITE_OK) return;
    return errorFromCode(rc);
}

fn errorFromCode(rc: c_int) Error {
    return switch (rc & 0xff) {
        c.SQLITE_BUSY => error.Busy,
        c.SQLITE_LOCKED => error.Locked,
        c.SQLITE_CONSTRAINT => error.Constraint,
        c.SQLITE_READONLY => error.ReadOnly,
        c.SQLITE_FULL => error.DiskFull,
        c.SQLITE_CANTOPEN => error.CantOpen,
        c.SQLITE_CORRUPT, c.SQLITE_NOTADB => error.Corrupt,
        c.SQLITE_IOERR => error.IoFailure,
        c.SQLITE_MISUSE => error.Misuse,
        c.SQLITE_NOMEM => error.OutOfMemory,
        else => error.SqliteFailure,
    };
}

pub const OpenFlags = struct {
    read_only: bool = false,
    create: bool = true,
};

pub const Conn = struct {
    handle: *c.sqlite3,

    /// Opens a connection in multi-thread mode: the connection itself must
    /// not be used by two threads at once (see `Pool`).
    pub fn open(path: [:0]const u8, flags: OpenFlags) Error!Conn {
        var raw: c_int = c.SQLITE_OPEN_NOMUTEX | c.SQLITE_OPEN_EXRESCODE;
        raw |= if (flags.read_only) c.SQLITE_OPEN_READONLY else c.SQLITE_OPEN_READWRITE;
        if (flags.create and !flags.read_only) raw |= c.SQLITE_OPEN_CREATE;

        var handle: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(path.ptr, &handle, raw, null);
        if (rc != c.SQLITE_OK) {
            if (handle) |h| {
                log.err("cannot open '{s}': {s}", .{ path, std.mem.span(c.sqlite3_errmsg(h)) });
                _ = c.sqlite3_close_v2(h);
            }
            return errorFromCode(rc);
        }
        return .{ .handle = handle.? };
    }

    pub fn close(conn: Conn) void {
        _ = c.sqlite3_close_v2(conn.handle);
    }

    /// The most recent error message of this connection.
    pub fn errmsg(conn: Conn) []const u8 {
        return std.mem.span(c.sqlite3_errmsg(conn.handle));
    }

    pub fn busyTimeout(conn: Conn, ms: u31) Error!void {
        try check(c.sqlite3_busy_timeout(conn.handle, ms));
    }

    /// Runs one or more SQL statements that take no parameters and return no
    /// rows of interest.
    pub fn execScript(conn: Conn, sql: [:0]const u8) Error!void {
        var msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(conn.handle, sql.ptr, null, null, &msg);
        defer if (msg != null) c.sqlite3_free(msg);
        if (rc != c.SQLITE_OK) {
            log.err("exec failed: {s}", .{if (msg != null) std.mem.span(msg) else conn.errmsg()});
            return errorFromCode(rc);
        }
    }

    /// Prepares, binds and runs a statement to completion, ignoring rows.
    pub fn exec(conn: Conn, sql: []const u8, args: anytype) Error!void {
        var stmt = try conn.prepare(sql);
        defer stmt.finalize();
        try stmt.bindAll(args);
        while (try stmt.step()) {}
    }

    pub fn prepare(conn: Conn, sql: []const u8) Error!Stmt {
        var handle: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(conn.handle, sql.ptr, @intCast(sql.len), &handle, null);
        if (rc != c.SQLITE_OK) {
            log.err("prepare failed: {s}: {s}", .{ conn.errmsg(), sql });
            return errorFromCode(rc);
        }
        return .{ .handle = handle.?, .conn = conn };
    }

    pub fn lastInsertRowId(conn: Conn) i64 {
        return c.sqlite3_last_insert_rowid(conn.handle);
    }

    /// Rows modified by the most recent INSERT, UPDATE or DELETE.
    pub fn changes(conn: Conn) i64 {
        return c.sqlite3_changes64(conn.handle);
    }

    pub const TransactionKind = enum { deferred, immediate };

    /// Starts a transaction. Use `.immediate` for transactions that write, so
    /// that lock contention is resolved by the busy timeout instead of failing
    /// with `error.Busy` on the first write.
    pub fn begin(conn: Conn, kind: TransactionKind) Error!void {
        try conn.execScript(switch (kind) {
            .deferred => "BEGIN DEFERRED",
            .immediate => "BEGIN IMMEDIATE",
        });
    }

    pub fn commit(conn: Conn) Error!void {
        try conn.execScript("COMMIT");
    }

    /// Rolls back the open transaction, if any. Safe to call from `errdefer`.
    pub fn rollback(conn: Conn) void {
        if (c.sqlite3_get_autocommit(conn.handle) != 0) return;
        conn.execScript("ROLLBACK") catch {};
    }
};

pub const Stmt = struct {
    handle: *c.sqlite3_stmt,
    conn: Conn,

    pub fn finalize(stmt: Stmt) void {
        _ = c.sqlite3_finalize(stmt.handle);
    }

    /// Makes the statement ready to run again; bindings are kept.
    pub fn reset(stmt: Stmt) void {
        _ = c.sqlite3_reset(stmt.handle);
    }

    pub fn clearBindings(stmt: Stmt) void {
        _ = c.sqlite3_clear_bindings(stmt.handle);
    }

    /// Advances to the next row. Returns `true` if a row is available and
    /// `false` once the statement has finished.
    pub fn step(stmt: Stmt) Error!bool {
        const rc = c.sqlite3_step(stmt.handle);
        return switch (rc) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => {
                log.debug("step failed: {s}", .{stmt.conn.errmsg()});
                return errorFromCode(rc);
            },
        };
    }

    /// Binds every field of the tuple `args` to parameters 1, 2, … in order.
    pub fn bindAll(stmt: Stmt, args: anytype) Error!void {
        inline for (args, 1..) |arg, index| {
            try stmt.bind(index, arg);
        }
    }

    /// Binds `value` to the 1-based parameter `index`. Supported types are
    /// integers, booleans, strings (bound as TEXT), optionals and `null`.
    pub fn bind(stmt: Stmt, index: c_int, value: anytype) Error!void {
        const T = @TypeOf(value);
        const rc = switch (@typeInfo(T)) {
            .null => c.sqlite3_bind_null(stmt.handle, index),
            .optional => return if (value) |v| stmt.bind(index, v) else stmt.bind(index, null),
            .bool => c.sqlite3_bind_int64(stmt.handle, index, @intFromBool(value)),
            .int, .comptime_int => c.sqlite3_bind_int64(stmt.handle, index, @intCast(value)),
            .float, .comptime_float => c.sqlite3_bind_double(stmt.handle, index, value),
            else => blk: {
                const text: []const u8 = value;
                break :blk c.sqlite3_bind_text64(stmt.handle, index, text.ptr, text.len, c.SQLITE_STATIC, c.SQLITE_UTF8);
            },
        };
        try check(rc);
    }

    pub fn columnIsNull(stmt: Stmt, index: c_int) bool {
        return c.sqlite3_column_type(stmt.handle, index) == c.SQLITE_NULL;
    }

    pub fn columnInt(stmt: Stmt, index: c_int) i64 {
        return c.sqlite3_column_int64(stmt.handle, index);
    }

    /// The TEXT value of a column. Valid until the next `step`, `reset` or
    /// `finalize`; use `columnTextDupe` to keep it.
    pub fn columnText(stmt: Stmt, index: c_int) []const u8 {
        const ptr = c.sqlite3_column_text(stmt.handle, index);
        const len: usize = @intCast(c.sqlite3_column_bytes(stmt.handle, index));
        if (ptr == null) return "";
        return ptr[0..len];
    }

    pub fn columnTextDupe(stmt: Stmt, gpa: std.mem.Allocator, index: c_int) error{OutOfMemory}![]u8 {
        return gpa.dupe(u8, stmt.columnText(index));
    }
};

test "open, write and read back" {
    const conn = try Conn.open(":memory:", .{});
    defer conn.close();

    try conn.execScript("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL, n INTEGER)");
    try conn.exec("INSERT INTO t (name, n) VALUES (?, ?)", .{ "alpha", 7 });
    try std.testing.expectEqual(1, conn.lastInsertRowId());
    try conn.exec("INSERT INTO t (name, n) VALUES (?, ?)", .{ "beta", null });

    var stmt = try conn.prepare("SELECT id, name, n FROM t ORDER BY id");
    defer stmt.finalize();

    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(1, stmt.columnInt(0));
    try std.testing.expectEqualStrings("alpha", stmt.columnText(1));
    try std.testing.expectEqual(7, stmt.columnInt(2));

    try std.testing.expect(try stmt.step());
    try std.testing.expectEqualStrings("beta", stmt.columnText(1));
    try std.testing.expect(stmt.columnIsNull(2));

    try std.testing.expect(!try stmt.step());
}

test "constraint violations map to error.Constraint" {
    const conn = try Conn.open(":memory:", .{});
    defer conn.close();

    try conn.execScript("CREATE TABLE t (k TEXT PRIMARY KEY)");
    try conn.exec("INSERT INTO t VALUES (?)", .{"x"});
    try std.testing.expectError(error.Constraint, conn.exec("INSERT INTO t VALUES (?)", .{"x"}));
}

test "rollback discards a transaction" {
    const conn = try Conn.open(":memory:", .{});
    defer conn.close();

    try conn.execScript("CREATE TABLE t (k INTEGER)");
    try conn.begin(.immediate);
    try conn.exec("INSERT INTO t VALUES (1)", .{});
    conn.rollback();
    conn.rollback(); // no transaction open: a no-op

    var stmt = try conn.prepare("SELECT count(*) FROM t");
    defer stmt.finalize();
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(0, stmt.columnInt(0));
}
