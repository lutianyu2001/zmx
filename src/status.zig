//! Program status reports (OSC 7501) that a session's programs have sent.
//!
//! A program tells its terminal what it is doing with
//! `OSC 7501 ; state=<state>:id=<id>:<key>=<value>... ST`, and the terminal
//! keeps the last report of each id. Reports pass through zmx to the attached
//! terminals untouched, but a terminal that attaches later has seen none of
//! them, and a snapshot of the screen doesn't carry them. The daemon therefore
//! keeps what a terminal following along would hold, and sends it after the
//! snapshot on attach.

const std = @import("std");
const testing = std.testing;

/// Reports longer than this are passed through but not kept.
pub const MAX_REPORT_LEN = 4096;

/// A terminal is asked to keep at least this many records, and to drop the
/// one updated longest ago beyond its limit.
pub const MAX_RECORDS = 64;

const Record = struct {
    id: []const u8,
    /// The report as sent, without the `7501;` in front.
    report: []const u8,
    /// `done` or `error`: a result, which outlives the program.
    finished: bool,
    updated: u64,

    fn deinit(self: Record, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.report);
    }
};

/// The last report of each id, as the rules of the protocol leave them.
pub const Records = struct {
    list: std.ArrayList(Record) = .empty,
    clock: u64 = 0,

    pub fn deinit(self: *Records, gpa: std.mem.Allocator) void {
        for (self.list.items) |record| record.deinit(gpa);
        self.list.deinit(gpa);
    }

    /// Take in one report (the text after `7501;`). One without a state is
    /// not a report and is ignored.
    pub fn apply(self: *Records, gpa: std.mem.Allocator, report: []const u8) !void {
        const state = field(report, "state") orelse return;
        const id = field(report, "id") orelse "";

        if (std.mem.eql(u8, state, "clear")) {
            // `clear` removes an id and the ids beneath it; without an id, all.
            var i: usize = 0;
            while (i < self.list.items.len) {
                const record = self.list.items[i];
                if (id.len == 0 or isAtOrBeneath(record.id, id)) {
                    self.list.orderedRemove(i).deinit(gpa);
                } else {
                    i += 1;
                }
            }
            return;
        }

        const owned_id = try gpa.dupe(u8, id);
        errdefer gpa.free(owned_id);
        const owned_report = try gpa.dupe(u8, report);
        errdefer gpa.free(owned_report);

        self.clock += 1;
        const record: Record = .{
            .id = owned_id,
            .report = owned_report,
            .finished = std.mem.eql(u8, state, "done") or std.mem.eql(u8, state, "error"),
            .updated = self.clock,
        };

        // A report replaces the record of its id. The list stays ordered by
        // update, so the replaced one moves to the end.
        for (self.list.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing.id, id)) {
                self.list.orderedRemove(i).deinit(gpa);
                break;
            }
        }
        try self.list.append(gpa, record);
        if (self.list.items.len > MAX_RECORDS) self.list.orderedRemove(0).deinit(gpa);
    }

    /// The command has ended (OSC 133;D): what it reported as still going on
    /// is over, also when it was killed before it could say so. Results stay
    /// until the program replaces or clears them.
    pub fn dropUnfinished(self: *Records, gpa: std.mem.Allocator) void {
        var i: usize = 0;
        while (i < self.list.items.len) {
            if (self.list.items[i].finished) {
                i += 1;
            } else {
                self.list.orderedRemove(i).deinit(gpa);
            }
        }
    }

    /// Write every record as the report it came in, oldest first.
    pub fn write(self: *const Records, writer: *std.Io.Writer) !void {
        for (self.list.items) |record| {
            try writer.print("\x1b]7501;{s}\x1b\\", .{record.report});
        }
    }
};

/// The value of `key` in a report: fields are separated by `:`, each `key=value`.
fn field(report: []const u8, key: []const u8) ?[]const u8 {
    var fields = std.mem.splitScalar(u8, report, ':');
    while (fields.next()) |entry| {
        const eq = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
        if (std.mem.eql(u8, entry[0..eq], key)) return entry[eq + 1 ..];
    }
    return null;
}

/// Ids form a tree with `/` between the levels.
fn isAtOrBeneath(id: []const u8, parent: []const u8) bool {
    if (!std.mem.startsWith(u8, id, parent)) return false;
    return id.len == parent.len or id[parent.len] == '/';
}

/// Finds the OSC sequences in PTY output that concern `Records`, across the
/// boundaries of the reads that deliver it.
pub const Scanner = struct {
    state: enum { ground, escape, osc, osc_escape } = .ground,
    buf: [MAX_REPORT_LEN + "7501;".len]u8 = undefined,
    len: usize = 0,
    /// The sequence being read no longer fits and is skipped to its end.
    overflow: bool = false,

    pub fn feed(self: *Scanner, gpa: std.mem.Allocator, records: *Records, data: []const u8) void {
        for (data) |byte| {
            switch (self.state) {
                .ground => if (byte == 0x1b) {
                    self.state = .escape;
                },
                .escape => if (byte == ']') {
                    self.state = .osc;
                    self.len = 0;
                    self.overflow = false;
                } else if (byte != 0x1b) {
                    self.state = .ground;
                },
                .osc => switch (byte) {
                    0x07 => self.finish(gpa, records),
                    0x1b => self.state = .osc_escape,
                    else => self.push(byte),
                },
                // ESC inside an OSC: `\` ends it (ST); anything else is not
                // ours to interpret, so the sequence is given up.
                .osc_escape => if (byte == '\\') {
                    self.finish(gpa, records);
                } else {
                    self.state = if (byte == 0x1b) .escape else .ground;
                },
            }
        }
    }

    fn push(self: *Scanner, byte: u8) void {
        if (self.len == self.buf.len) {
            self.overflow = true;
            return;
        }
        self.buf[self.len] = byte;
        self.len += 1;
    }

    fn finish(self: *Scanner, gpa: std.mem.Allocator, records: *Records) void {
        self.state = .ground;
        if (self.overflow) return;
        const osc = self.buf[0..self.len];

        if (std.mem.startsWith(u8, osc, "7501;")) {
            records.apply(gpa, osc["7501;".len..]) catch |err| {
                std.log.warn("failed to keep program status err={s}", .{@errorName(err)});
            };
        } else if (std.mem.eql(u8, osc, "133;D") or std.mem.startsWith(u8, osc, "133;D;")) {
            records.dropUnfinished(gpa);
        }
    }
};

fn expectWritten(records: *const Records, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try records.write(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

test "Records: a report replaces the record of its id" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);

    try records.apply(testing.allocator, "state=working:id=a:app=vim");
    try records.apply(testing.allocator, "state=idle:id=b");
    try records.apply(testing.allocator, "state=done:id=a:app=vim");

    // Oldest update first.
    try expectWritten(&records, "\x1b]7501;state=idle:id=b\x1b\\" ++
        "\x1b]7501;state=done:id=a:app=vim\x1b\\");
}

test "Records: the root record has no id" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);

    try records.apply(testing.allocator, "state=working");
    try records.apply(testing.allocator, "app=x:state=blocked");
    try expectWritten(&records, "\x1b]7501;app=x:state=blocked\x1b\\");
}

test "Records: clear removes an id and the ids beneath it" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);

    try records.apply(testing.allocator, "state=idle:id=sh");
    try records.apply(testing.allocator, "state=working:id=sh/cmd");
    try records.apply(testing.allocator, "state=working:id=shell");
    try records.apply(testing.allocator, "state=clear:id=sh");
    try expectWritten(&records, "\x1b]7501;state=working:id=shell\x1b\\");

    try records.apply(testing.allocator, "state=working:id=other");
    try records.apply(testing.allocator, "state=clear");
    try expectWritten(&records, "");
}

test "Records: a report without a state is ignored" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);

    try records.apply(testing.allocator, "id=a:app=vim");
    try records.apply(testing.allocator, "");
    try expectWritten(&records, "");
}

test "Records: the end of a command keeps only results" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);

    try records.apply(testing.allocator, "state=working:id=a");
    try records.apply(testing.allocator, "state=done:id=b");
    try records.apply(testing.allocator, "state=blocked:id=c");
    try records.apply(testing.allocator, "state=error:id=d");
    try records.apply(testing.allocator, "state=idle:id=e");
    records.dropUnfinished(testing.allocator);

    try expectWritten(&records, "\x1b]7501;state=done:id=b\x1b\\" ++
        "\x1b]7501;state=error:id=d\x1b\\");
}

test "Records: beyond the limit the record updated longest ago goes" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);

    var buf: [32]u8 = undefined;
    for (0..MAX_RECORDS + 1) |i| {
        // Keep id 0 fresh, so that id 1 is the oldest when the limit is passed.
        if (i == MAX_RECORDS) try records.apply(testing.allocator, "state=idle:id=0");
        try records.apply(testing.allocator, try std.fmt.bufPrint(&buf, "state=idle:id={d}", .{i}));
    }

    try testing.expectEqual(MAX_RECORDS, records.list.items.len);
    for (records.list.items) |record| try testing.expect(!std.mem.eql(u8, record.id, "1"));
    try testing.expectEqualStrings("0", records.list.items[MAX_RECORDS - 2].id);
}

test "Scanner: finds reports among other output, with either terminator" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);
    var scanner: Scanner = .{};

    scanner.feed(testing.allocator, &records, "text\x1b[1m\x1b]0;title\x07" ++
        "\x1b]7501;state=working:id=a\x07more\x1b]7501;state=idle:id=b\x1b\\");
    try expectWritten(&records, "\x1b]7501;state=working:id=a\x1b\\" ++
        "\x1b]7501;state=idle:id=b\x1b\\");
}

test "Scanner: a report split across reads" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);
    var scanner: Scanner = .{};

    const report = "\x1b]7501;state=working:id=a\x1b\\";
    for (report) |byte| scanner.feed(testing.allocator, &records, &.{byte});
    try expectWritten(&records, report);
}

test "Scanner: the end of a command drops what was unfinished" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);
    var scanner: Scanner = .{};

    scanner.feed(testing.allocator, &records, "\x1b]7501;state=working:id=a\x07" ++
        "\x1b]7501;state=done:id=b\x07");
    // A prompt start is not the end of a command; 133;D is, with or without an exit code.
    scanner.feed(testing.allocator, &records, "\x1b]133;A\x07");
    try testing.expectEqual(2, records.list.items.len);
    scanner.feed(testing.allocator, &records, "\x1b]133;D;0\x07");
    try expectWritten(&records, "\x1b]7501;state=done:id=b\x1b\\");

    scanner.feed(testing.allocator, &records, "\x1b]7501;state=working:id=a\x07\x1b]133;D\x1b\\");
    try expectWritten(&records, "\x1b]7501;state=done:id=b\x1b\\");
}

test "Scanner: a report too long to keep is skipped, and the next one is read" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);
    var scanner: Scanner = .{};

    const filler: [MAX_REPORT_LEN + 1]u8 = @splat('x');
    scanner.feed(testing.allocator, &records, "\x1b]7501;state=working:id=a:msg=");
    scanner.feed(testing.allocator, &records, &filler);
    scanner.feed(testing.allocator, &records, "\x07\x1b]7501;state=idle:id=b\x07");
    try expectWritten(&records, "\x1b]7501;state=idle:id=b\x1b\\");
}

test "Scanner: an OSC broken off by another escape is given up" {
    var records: Records = .{};
    defer records.deinit(testing.allocator);
    var scanner: Scanner = .{};

    scanner.feed(testing.allocator, &records, "\x1b]7501;state=working:id=a\x1b[0m\x07");
    try expectWritten(&records, "");
    scanner.feed(testing.allocator, &records, "\x1b]7501;state=working\x1b\x1b]7501;state=idle:id=b\x07");
    try expectWritten(&records, "\x1b]7501;state=idle:id=b\x1b\\");
}
