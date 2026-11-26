//! Minimal HTTP/1.1 message handling: request heads, request bodies
//! (`Content-Length` or chunked) and responses.
//!
//! The server answers exactly one request per connection, so responses always
//! carry `Connection: close`.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Status = std.http.Status;

/// Upper bound for the request line plus all header fields. Also the size of
/// the connection read buffer, since the whole head is parsed in place.
pub const max_head_len = 16 * 1024;

pub const Version = enum { @"HTTP/1.0", @"HTTP/1.1" };

pub const Head = struct {
    method: []const u8,
    target: []const u8,
    version: Version,
    content_length: ?u64 = null,
    chunked: bool = false,
    expect_continue: bool = false,

    pub fn hasBody(head: Head) bool {
        return head.chunked or (head.content_length orelse 0) > 0;
    }
};

pub const HeadError = error{
    /// The client closed the connection before sending a complete head.
    EndOfStream,
    ReadFailed,
    /// The head exceeds `max_head_len`.
    HeadTooLarge,
    /// The head is not a well-formed HTTP/1.x request.
    BadRequest,
    /// The request carries an `Expect` value other than `100-continue`.
    ExpectationFailed,
};

/// Reads a request head from `in` and parses it. The returned strings point
/// into the buffer of `in` and are invalidated by the next read from `in`.
///
/// Asserts the buffer of `in` holds at least `max_head_len` bytes.
pub fn readHead(in: *Io.Reader) HeadError!Head {
    std.debug.assert(in.buffer.len >= max_head_len);
    var parser: std.http.HeadParser = .{};
    var scanned: usize = 0;
    while (true) {
        const buffered = in.buffered();
        scanned += parser.feed(buffered[scanned..]);
        if (parser.state == .finished) break;
        if (buffered.len >= max_head_len) return error.HeadTooLarge;
        in.fillMore() catch |err| switch (err) {
            error.EndOfStream => return error.EndOfStream,
            error.ReadFailed => return error.ReadFailed,
        };
    }
    if (scanned > max_head_len) return error.HeadTooLarge;
    return parseHead(in.take(scanned) catch unreachable);
}

/// Parses a complete request head, including the terminating empty line.
pub fn parseHead(bytes: []const u8) HeadError!Head {
    var lines = std.mem.splitScalar(u8, bytes, '\n');

    const request_line = trimCr(lines.first());
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next().?;
    const target = parts.next() orelse return error.BadRequest;
    const version_text = parts.next() orelse return error.BadRequest;
    if (parts.next() != null) return error.BadRequest;
    if (!isToken(method) or target.len == 0) return error.BadRequest;
    const version = std.meta.stringToEnum(Version, version_text) orelse return error.BadRequest;

    var head: Head = .{ .method = method, .target = target, .version = version };
    var transfer_encoding = false;

    while (lines.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) break;
        const colon = std.mem.findScalar(u8, line, ':') orelse return error.BadRequest;
        const name = line[0..colon];
        if (!isToken(name)) return error.BadRequest;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            const length = parseContentLength(value) orelse return error.BadRequest;
            if (head.content_length) |previous| {
                if (previous != length) return error.BadRequest;
            }
            head.content_length = length;
        } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            transfer_encoding = true;
            // Only "chunked" as the final coding can be framed; anything else
            // leaves the body length undeterminable.
            var codings = std.mem.splitBackwardsScalar(u8, value, ',');
            const last = std.mem.trim(u8, codings.first(), " \t");
            head.chunked = std.ascii.eqlIgnoreCase(last, "chunked");
            if (!head.chunked) return error.BadRequest;
        } else if (std.ascii.eqlIgnoreCase(name, "expect")) {
            if (!std.ascii.eqlIgnoreCase(value, "100-continue")) return error.ExpectationFailed;
            head.expect_continue = true;
        }
    }

    // A message with both framings is a request smuggling vector.
    if (transfer_encoding and head.content_length != null) return error.BadRequest;
    return head;
}

fn trimCr(line: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

fn isToken(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9' => {},
        '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
        else => return false,
    };
    return true;
}

fn parseContentLength(value: []const u8) ?u64 {
    if (value.len == 0) return null;
    for (value) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseInt(u64, value, 10) catch null;
}

pub const BodyError = error{
    EndOfStream,
    ReadFailed,
    OutOfMemory,
    /// The body exceeds the caller's limit.
    TooLarge,
    /// The chunked encoding is malformed.
    BadRequest,
};

/// Reads the whole request body described by `head` into memory allocated
/// with `gpa`. The caller owns the returned slice.
///
/// When `head` declares a `Content-Length` above `limit`, returns
/// `error.TooLarge` without consuming any of the body.
pub fn readBody(in: *Io.Reader, gpa: Allocator, head: Head, limit: usize) BodyError![]u8 {
    if (head.chunked) {
        var body: std.ArrayList(u8) = .empty;
        errdefer body.deinit(gpa);
        try readChunked(in, .{ .gpa = gpa, .list = &body }, limit);
        return body.toOwnedSlice(gpa);
    }
    const length = head.content_length orelse 0;
    if (length > limit) return error.TooLarge;
    const body = try gpa.alloc(u8, @intCast(length));
    errdefer gpa.free(body);
    try in.readSliceAll(body);
    return body;
}

/// Consumes and drops the request body described by `head`, provided it is
/// no larger than `limit` bytes.
pub fn discardBody(in: *Io.Reader, head: Head, limit: usize) BodyError!void {
    if (head.chunked) return readChunked(in, null, limit);
    const length = head.content_length orelse 0;
    if (length > limit) return error.TooLarge;
    try in.discardAll64(length);
}

const Sink = struct {
    gpa: Allocator,
    list: *std.ArrayList(u8),
};

fn readChunked(in: *Io.Reader, sink: ?Sink, limit: usize) BodyError!void {
    var total: u64 = 0;
    while (true) {
        const size_line = try takeLine(in);
        const size_text = std.mem.trim(u8, size_line[0 .. std.mem.findScalar(u8, size_line, ';') orelse size_line.len], " \t");
        if (size_text.len == 0) return error.BadRequest;
        const size = std.fmt.parseInt(u64, size_text, 16) catch return error.BadRequest;
        if (size == 0) break;

        total = std.math.add(u64, total, size) catch return error.TooLarge;
        if (total > limit) return error.TooLarge;
        if (sink) |s| {
            const n: usize = @intCast(size);
            try s.list.ensureUnusedCapacity(s.gpa, n);
            try in.readSliceAll(s.list.unusedCapacitySlice()[0..n]);
            s.list.items.len += n;
        } else {
            try in.discardAll64(size);
        }
        if ((try takeLine(in)).len != 0) return error.BadRequest;
    }
    // Trailer fields are ignored; they end with an empty line.
    while ((try takeLine(in)).len != 0) {}
}

/// Takes one line, without its terminating LF or CRLF.
fn takeLine(in: *Io.Reader) BodyError![]u8 {
    const line = in.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.BadRequest,
        error.EndOfStream => return error.EndOfStream,
        error.ReadFailed => return error.ReadFailed,
    };
    const without_lf = line[0 .. line.len - 1];
    return if (std.mem.endsWith(u8, without_lf, "\r")) without_lf[0 .. without_lf.len - 1] else without_lf;
}

pub const Response = struct {
    status: Status,
    body: []const u8 = "",
    content_type: []const u8 = "text/plain; charset=utf-8",
    /// Value of the `Allow` header, sent with 405 responses.
    allow: ?[]const u8 = null,
    /// Omit the body (but keep its `Content-Length`), as for `HEAD` requests.
    elide_body: bool = false,

    /// A plain-text response whose body is the status' reason phrase.
    pub fn plain(status: Status) Response {
        return .{ .status = status, .body = status.phrase() orelse "" };
    }
};

/// Writes a complete response and flushes `out`.
pub fn writeResponse(out: *Io.Writer, response: Response) Io.Writer.Error!void {
    const status = response.status;
    try out.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status), status.phrase() orelse "" });
    if (response.allow) |allow| try out.print("Allow: {s}\r\n", .{allow});
    try out.print("Content-Length: {d}\r\n", .{response.body.len});
    if (response.body.len > 0) try out.print("Content-Type: {s}\r\n", .{response.content_type});
    try out.writeAll("Connection: close\r\n\r\n");
    if (!response.elide_body) try out.writeAll(response.body);
    try out.flush();
}

/// Tells a client that sent `Expect: 100-continue` to transmit the body.
pub fn writeContinue(out: *Io.Writer) Io.Writer.Error!void {
    try out.writeAll("HTTP/1.1 100 Continue\r\n\r\n");
    try out.flush();
}

const testing = std.testing;

test parseHead {
    const head = try parseHead("PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-LENGTH:  5 \r\nConnection: close\r\n\r\n");
    try testing.expectEqualStrings("PUT", head.method);
    try testing.expectEqualStrings("/kv/a", head.target);
    try testing.expectEqual(Version.@"HTTP/1.1", head.version);
    try testing.expectEqual(5, head.content_length);
    try testing.expect(!head.chunked);

    const chunked = try parseHead("POST / HTTP/1.1\nTransfer-Encoding: gzip, Chunked\n\n");
    try testing.expect(chunked.chunked);
    try testing.expect(chunked.hasBody());

    try testing.expectError(error.BadRequest, parseHead("GET /\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseHead("GET / HTTP/2.0\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseHead("GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseHead("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseHead("GET / HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n"));
    try testing.expectError(error.ExpectationFailed, parseHead("GET / HTTP/1.1\r\nExpect: nope\r\n\r\n"));
}

test readHead {
    var in: Io.Reader = .fixed("GET /health HTTP/1.1\r\n\r\nrest" ++ ("x" ** max_head_len));
    const head = try readHead(&in);
    try testing.expectEqualStrings("/health", head.target);
    try testing.expectEqualStrings("rest", in.buffered()[0..4]);

    var oversized: Io.Reader = .fixed("GET / HTTP/1.1\r\nX: " ++ ("x" ** max_head_len) ++ "\r\n\r\n");
    try testing.expectError(error.HeadTooLarge, readHead(&oversized));
}

test "chunked body" {
    const head: Head = .{ .method = "PUT", .target = "/", .version = .@"HTTP/1.1", .chunked = true };

    var in: Io.Reader = .fixed("5;ext=1\r\nhello\r\n6\r\n world\r\n0\r\nTrailer: x\r\n\r\nnext");
    const body = try readBody(&in, testing.allocator, head, 64);
    defer testing.allocator.free(body);
    try testing.expectEqualStrings("hello world", body);
    try testing.expectEqualStrings("next", in.buffered());

    var too_large: Io.Reader = .fixed("5\r\nhello\r\n0\r\n\r\n");
    try testing.expectError(error.TooLarge, readBody(&too_large, testing.allocator, head, 4));

    var malformed: Io.Reader = .fixed("zz\r\n");
    try testing.expectError(error.BadRequest, discardBody(&malformed, head, 64));
}

test "content-length body" {
    const head: Head = .{ .method = "PUT", .target = "/", .version = .@"HTTP/1.1", .content_length = 3 };
    var in: Io.Reader = .fixed("abcdef");
    const body = try readBody(&in, testing.allocator, head, 3);
    defer testing.allocator.free(body);
    try testing.expectEqualStrings("abc", body);
    try testing.expectError(error.TooLarge, readBody(&in, testing.allocator, head, 2));
    try discardBody(&in, head, 3);
    try testing.expectEqual(0, in.buffered().len);
}

test writeResponse {
    var buf: [256]u8 = undefined;
    var out: Io.Writer = .fixed(&buf);
    try writeResponse(&out, .{ .status = .method_not_allowed, .body = "nope", .allow = "GET" });
    try testing.expectEqualStrings(
        "HTTP/1.1 405 Method Not Allowed\r\nAllow: GET\r\nContent-Length: 4\r\n" ++
            "Content-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\nnope",
        out.buffered(),
    );
}
