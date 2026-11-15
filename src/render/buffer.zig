const std = @import("std");

/// Small allocator-aware string builder used by the help renderer.
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayList(u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Buffer) void {
        self.data.deinit(self.allocator);
    }

    pub fn append(self: *Buffer, text: []const u8) !void {
        try self.data.appendSlice(self.allocator, text);
    }

    pub fn appendFmt(
        self: *Buffer,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.append(text);
    }

    pub fn appendSpaces(self: *Buffer, count: usize) !void {
        try self.data.appendNTimes(self.allocator, ' ', count);
    }

    pub fn toOwnedSlice(self: *Buffer) ![]u8 {
        return try self.data.toOwnedSlice(self.allocator);
    }
};
