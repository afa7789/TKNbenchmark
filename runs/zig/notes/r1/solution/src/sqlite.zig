//! Thin, typed wrapper over the SQLite C API.

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
                log.err("open {s}: {s}", .{ path, std.mem.span(c.sqlite3_errmsg(h)) });
                _ = c.sqlite3_close(h);
            }
            return error.SqliteError;
        }
        return .{ .handle = handle.? };
    }

    pub fn close(db: Db) void {
        _ = c.sqlite3_close(db.handle);
    }

    /// Runs one or more statements that produce no rows of interest.
    pub fn exec(db: Db, sql: [:0]const u8) Error!void {
        var err_msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(db.handle, sql.ptr, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg) |m| {
                log.err("exec: {s}", .{std.mem.span(m)});
                c.sqlite3_free(m);
            }
            return error.SqliteError;
        }
    }

    pub fn prepare(db: Db, sql: []const u8) Error!Statement {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(db.handle, sql.ptr, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return db.fail("prepare");
        return .{ .db = db, .handle = stmt.? };
    }

    pub fn lastInsertRowId(db: Db) i64 {
        return c.sqlite3_last_insert_rowid(db.handle);
    }

    pub fn changes(db: Db) i64 {
        return c.sqlite3_changes64(db.handle);
    }

    fn fail(db: Db, what: []const u8) error{SqliteError} {
        log.err("{s}: {s}", .{ what, std.mem.span(c.sqlite3_errmsg(db.handle)) });
        return error.SqliteError;
    }
};

pub const Statement = struct {
    db: Db,
    handle: *c.sqlite3_stmt,

    pub fn finalize(s: Statement) void {
        _ = c.sqlite3_finalize(s.handle);
    }

    /// Makes the statement ready to run again; bindings are kept.
    pub fn reset(s: Statement) void {
        _ = c.sqlite3_reset(s.handle);
    }

    /// Binds a value to the 1-based parameter `index`. Text is bound without
    /// copying, so it must outlive the statement's next `step`/`reset`.
    pub fn bind(s: Statement, index: c_int, value: anytype) Error!void {
        const T = @TypeOf(value);
        const rc = switch (@typeInfo(T)) {
            .null => c.sqlite3_bind_null(s.handle, index),
            .int, .comptime_int => c.sqlite3_bind_int64(s.handle, index, @intCast(value)),
            .optional => if (value) |v| return s.bind(index, v) else c.sqlite3_bind_null(s.handle, index),
            else => if (comptime isString(T))
                c.sqlite3_bind_text64(s.handle, index, @as([]const u8, value).ptr, @as([]const u8, value).len, null, c.SQLITE_UTF8)
            else
                @compileError("cannot bind value of type " ++ @typeName(T)),
        };
        if (rc != c.SQLITE_OK) return s.db.fail("bind");
    }

    /// Binds all values of a tuple to parameters 1, 2, ...
    pub fn bindAll(s: Statement, values: anytype) Error!void {
        inline for (values, 1..) |v, i| try s.bind(@intCast(i), v);
    }

    /// Advances the statement; returns true while a row is available.
    pub fn step(s: Statement) Error!bool {
        return switch (c.sqlite3_step(s.handle)) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => s.db.fail("step"),
        };
    }

    /// Runs a statement that returns no rows.
    pub fn run(s: Statement) Error!void {
        while (try s.step()) {}
    }

    pub fn columnInt(s: Statement, col: c_int) i64 {
        return c.sqlite3_column_int64(s.handle, col);
    }

    /// Text of a column of the current row; valid until the next `step`.
    pub fn columnText(s: Statement, col: c_int) []const u8 {
        const ptr = c.sqlite3_column_text(s.handle, col) orelse return "";
        const len: usize = @intCast(c.sqlite3_column_bytes(s.handle, col));
        return ptr[0..len];
    }

    fn isString(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .pointer => |p| switch (p.size) {
                .slice => p.child == u8,
                .one => switch (@typeInfo(p.child)) {
                    .array => |a| a.child == u8,
                    else => false,
                },
                else => false,
            },
            else => false,
        };
    }
};

test "round trip through an in-memory database" {
    const db = try Db.open(":memory:");
    defer db.close();
    try db.exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");

    const ins = try db.prepare("INSERT INTO t (name) VALUES (?1)");
    defer ins.finalize();
    try ins.bind(1, "alpha");
    try ins.run();
    try std.testing.expectEqual(@as(i64, 1), db.lastInsertRowId());

    const sel = try db.prepare("SELECT id, name FROM t WHERE id = ?1");
    defer sel.finalize();
    try sel.bindAll(.{@as(i64, 1)});
    try std.testing.expect(try sel.step());
    try std.testing.expectEqual(@as(i64, 1), sel.columnInt(0));
    try std.testing.expectEqualStrings("alpha", sel.columnText(1));
    try std.testing.expect(!try sel.step());
}
