//! A thin, typed wrapper over the SQLite C API.
//!
//! Only the small surface this service needs is exposed: opening a
//! connection, executing SQL, and prepared statements with typed binding and
//! column access. Errors are reported as `error.Sqlite`; the connection's
//! `errorMessage` describes the most recent failure.

const std = @import("std");
const c = @import("sqlite3");

const log = std.log.scoped(.sqlite);

pub const Error = error{Sqlite};

pub const Db = struct {
    handle: *c.sqlite3,

    pub const OpenOptions = struct {
        /// How long a statement waits for a lock held by another connection.
        busy_timeout_ms: c_int = 5000,
    };

    /// Opens (creating if needed) the database at `path`. Use `":memory:"`
    /// for a private in-memory database.
    pub fn open(path: [:0]const u8, options: OpenOptions) Error!Db {
        var handle: ?*c.sqlite3 = null;
        const flags = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX;
        const rc = c.sqlite3_open_v2(path.ptr, &handle, flags, null);
        if (rc != c.SQLITE_OK) {
            if (handle) |h| {
                log.err("cannot open {s}: {s}", .{ path, std.mem.span(c.sqlite3_errmsg(h)) });
                _ = c.sqlite3_close_v2(h);
            } else {
                log.err("cannot open {s}: {s}", .{ path, std.mem.span(c.sqlite3_errstr(rc)) });
            }
            return error.Sqlite;
        }
        const db: Db = .{ .handle = handle.? };
        _ = c.sqlite3_extended_result_codes(db.handle, 1);
        _ = c.sqlite3_busy_timeout(db.handle, options.busy_timeout_ms);
        return db;
    }

    pub fn close(db: Db) void {
        _ = c.sqlite3_close_v2(db.handle);
    }

    /// Message describing the most recent failed call on this connection.
    pub fn errorMessage(db: Db) []const u8 {
        return std.mem.span(c.sqlite3_errmsg(db.handle));
    }

    /// Executes one or more SQL statements that return no rows.
    pub fn exec(db: Db, sql: [:0]const u8) Error!void {
        const rc = c.sqlite3_exec(db.handle, sql.ptr, null, null, null);
        if (rc != c.SQLITE_OK) return db.fail("exec");
    }

    /// Compiles a single SQL statement. The caller must `deinit` it.
    pub fn prepare(db: Db, sql: []const u8) Error!Statement {
        var handle: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(db.handle, sql.ptr, @intCast(sql.len), &handle, null);
        if (rc != c.SQLITE_OK) return db.fail("prepare");
        return .{ .db = db, .handle = handle orelse return db.fail("prepare (empty statement)") };
    }

    /// Prepares `sql`, binds `args` and runs it to completion.
    pub fn run(db: Db, sql: []const u8, args: anytype) Error!void {
        var stmt = try db.prepare(sql);
        defer stmt.deinit();
        try stmt.bindAll(args);
        while (try stmt.step()) {}
    }

    /// Rowid of the most recent successful INSERT on this connection.
    pub fn lastInsertRowId(db: Db) i64 {
        return c.sqlite3_last_insert_rowid(db.handle);
    }

    /// Number of rows changed by the most recent INSERT, UPDATE or DELETE.
    pub fn changes(db: Db) i64 {
        return c.sqlite3_changes64(db.handle);
    }

    pub fn begin(db: Db) Error!void {
        try db.exec("BEGIN IMMEDIATE");
    }

    pub fn commit(db: Db) Error!void {
        try db.exec("COMMIT");
    }

    /// Rolls back the open transaction, if any. Meant for `errdefer`, so it
    /// logs instead of returning an error.
    pub fn rollback(db: Db) void {
        if (c.sqlite3_get_autocommit(db.handle) != 0) return;
        db.exec("ROLLBACK") catch {};
    }

    fn fail(db: Db, what: []const u8) error{Sqlite} {
        log.warn("{s}: {s}", .{ what, db.errorMessage() });
        return error.Sqlite;
    }
};

pub const Statement = struct {
    db: Db,
    handle: *c.sqlite3_stmt,

    pub fn deinit(stmt: *Statement) void {
        _ = c.sqlite3_finalize(stmt.handle);
        stmt.* = undefined;
    }

    /// Binds every field of the tuple `args` to parameters 1, 2, ….
    pub fn bindAll(stmt: Statement, args: anytype) Error!void {
        inline for (args, 1..) |arg, index| try stmt.bind(index, arg);
    }

    /// Binds `value` to the 1-based parameter `index`. Supported values are
    /// integers, strings (`[]const u8`), optionals of those, and `null`.
    ///
    /// Strings are bound without copying: they must stay valid until the
    /// statement is reset or finalized.
    pub fn bind(stmt: Statement, index: usize, value: anytype) Error!void {
        const i: c_int = @intCast(index);
        const T = @TypeOf(value);
        const rc = switch (@typeInfo(T)) {
            .null => c.sqlite3_bind_null(stmt.handle, i),
            .optional => if (value) |v| return stmt.bind(index, v) else c.sqlite3_bind_null(stmt.handle, i),
            .int, .comptime_int => c.sqlite3_bind_int64(stmt.handle, i, @intCast(value)),
            .bool => c.sqlite3_bind_int64(stmt.handle, i, @intFromBool(value)),
            else => blk: {
                const text: []const u8 = value;
                break :blk c.sqlite3_bind_text64(stmt.handle, i, text.ptr, text.len, c.SQLITE_STATIC, c.SQLITE_UTF8);
            },
        };
        if (rc != c.SQLITE_OK) return stmt.db.fail("bind");
    }

    /// Advances to the next row. Returns `false` once the statement is done.
    pub fn step(stmt: Statement) Error!bool {
        return switch (c.sqlite3_step(stmt.handle)) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => stmt.db.fail("step"),
        };
    }

    /// Resets the statement so it can be executed again with new bindings.
    pub fn reset(stmt: Statement) void {
        _ = c.sqlite3_reset(stmt.handle);
        _ = c.sqlite3_clear_bindings(stmt.handle);
    }

    pub fn columnInt(stmt: Statement, index: usize) i64 {
        return c.sqlite3_column_int64(stmt.handle, @intCast(index));
    }

    /// Text of a column in the current row. The slice is only valid until
    /// the next call to `step`, `reset` or `deinit`; copy it to keep it.
    pub fn columnText(stmt: Statement, index: usize) []const u8 {
        const i: c_int = @intCast(index);
        const ptr = c.sqlite3_column_text(stmt.handle, i) orelse return "";
        const len: usize = @intCast(c.sqlite3_column_bytes(stmt.handle, i));
        return ptr[0..len];
    }

    /// Like `columnText`, but copies the text into `allocator`.
    pub fn columnTextAlloc(stmt: Statement, allocator: std.mem.Allocator, index: usize) error{OutOfMemory}![]u8 {
        return allocator.dupe(u8, stmt.columnText(index));
    }
};

test "exec, bind and read back rows" {
    const db = try Db.open(":memory:", .{});
    defer db.close();

    try db.exec("CREATE TABLE t (n INTEGER NOT NULL, s TEXT)");
    try db.run("INSERT INTO t (n, s) VALUES (?, ?)", .{ 7, "seven" });
    try db.run("INSERT INTO t (n, s) VALUES (?, ?)", .{ 8, null });
    try std.testing.expectEqual(@as(i64, 2), db.lastInsertRowId());

    var stmt = try db.prepare("SELECT n, s FROM t ORDER BY n");
    defer stmt.deinit();
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(@as(i64, 7), stmt.columnInt(0));
    try std.testing.expectEqualStrings("seven", stmt.columnText(1));
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqualStrings("", stmt.columnText(1));
    try std.testing.expect(!try stmt.step());
}

test "rollback discards an open transaction" {
    const db = try Db.open(":memory:", .{});
    defer db.close();

    try db.exec("CREATE TABLE t (n INTEGER)");
    try db.begin();
    try db.run("INSERT INTO t VALUES (?)", .{1});
    db.rollback();
    db.rollback(); // no transaction: a no-op

    var stmt = try db.prepare("SELECT count(*) FROM t");
    defer stmt.deinit();
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(@as(i64, 0), stmt.columnInt(0));
}

test "errors are reported" {
    const db = try Db.open(":memory:", .{});
    defer db.close();
    try std.testing.expectError(error.Sqlite, db.exec("NOT SQL"));
}
