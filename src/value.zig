const std = @import("std");
const command = @import("command.zig");

pub const Source = enum {
    command_line,
    environment,
    default,
    implicit,
};

pub const Value = union(enum) {
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
};

/// One parsed value. Multiple entries with the same name represent a
/// repeatable option or a variadic positional argument.
pub const Entry = struct {
    name: []const u8,
    value: Value,
    source: Source,
    owner: *const command.Command,
};

pub fn parse(kind: command.ValueKind, raw: []const u8) error{InvalidValue}!Value {
    return switch (kind) {
        .boolean => .{ .boolean = try parseBoolean(raw) },
        .integer => .{
            .integer = std.fmt.parseInt(i64, raw, 10) catch
                return error.InvalidValue,
        },
        .float => .{
            .float = std.fmt.parseFloat(f64, raw) catch
                return error.InvalidValue,
        },
        .string => .{ .string = raw },
    };
}

pub fn parseBoolean(raw: []const u8) error{InvalidValue}!bool {
    if (std.mem.eql(u8, raw, "true") or
        std.mem.eql(u8, raw, "1") or
        std.mem.eql(u8, raw, "yes") or
        std.mem.eql(u8, raw, "on"))
    {
        return true;
    }

    if (std.mem.eql(u8, raw, "false") or
        std.mem.eql(u8, raw, "0") or
        std.mem.eql(u8, raw, "no") or
        std.mem.eql(u8, raw, "off"))
    {
        return false;
    }

    return error.InvalidValue;
}
