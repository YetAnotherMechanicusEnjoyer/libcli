const std = @import("std");
const command = @import("../command.zig");
const color = @import("../color.zig");
const value = @import("../value.zig");

pub const EnvironmentVariable = struct {
    name: []const u8,
    value: []const u8,
};

pub const Options = struct {
    /// Values are supplied by the caller so the parser has no process-global
    /// environment dependency.
    environment: []const EnvironmentVariable = &.{},
    color: color.ColorMode = .auto,
};

pub const Parsed = struct {
    allocator: std.mem.Allocator,
    command: *const command.Command,
    options: []value.Entry,
    arguments: []value.Entry,
    color_mode: color.ColorMode,
    no_color_env: bool,

    pub fn deinit(self: *Parsed) void {
        self.allocator.free(self.options);
        self.allocator.free(self.arguments);
        self.* = undefined;
    }

    pub fn get_option(self: *const Parsed, name: []const u8) ?value.Value {
        return getLast(self.options, name);
    }

    pub fn get_argument(self: *const Parsed, name: []const u8) ?value.Value {
        return getLast(self.arguments, name);
    }

    pub fn get_bool(self: *const Parsed, name: []const u8) ?bool {
        const item = self.get_option(name) orelse return null;
        return switch (item) {
            .boolean => |parsed| parsed,
            else => null,
        };
    }

    pub fn get_int(self: *const Parsed, name: []const u8) ?i64 {
        const item = self.get_option(name) orelse return null;
        return switch (item) {
            .integer => |parsed| parsed,
            else => null,
        };
    }

    pub fn get_float(self: *const Parsed, name: []const u8) ?f64 {
        const item = self.get_option(name) orelse return null;
        return switch (item) {
            .float => |parsed| parsed,
            else => null,
        };
    }

    pub fn get_string(self: *const Parsed, name: []const u8) ?[]const u8 {
        const item = self.get_option(name) orelse return null;
        return switch (item) {
            .string => |parsed| parsed,
            else => null,
        };
    }

    pub fn get_argument_string(
        self: *const Parsed,
        name: []const u8,
    ) ?[]const u8 {
        const item = self.get_argument(name) orelse return null;
        return switch (item) {
            .string => |parsed| parsed,
            else => null,
        };
    }

    pub fn get_argument_bool(self: *const Parsed, name: []const u8) ?bool {
        const item = self.get_argument(name) orelse return null;
        return switch (item) {
            .boolean => |parsed| parsed,
            else => null,
        };
    }

    pub fn get_argument_int(self: *const Parsed, name: []const u8) ?i64 {
        const item = self.get_argument(name) orelse return null;
        return switch (item) {
            .integer => |parsed| parsed,
            else => null,
        };
    }

    pub fn get_argument_float(self: *const Parsed, name: []const u8) ?f64 {
        const item = self.get_argument(name) orelse return null;
        return switch (item) {
            .float => |parsed| parsed,
            else => null,
        };
    }

    /// Returns where the effective value of an option came from.
    pub fn get_option_source(
        self: *const Parsed,
        name: []const u8,
    ) ?value.Source {
        return getLastSource(self.options, name);
    }

    pub fn get_argument_source(
        self: *const Parsed,
        name: []const u8,
    ) ?value.Source {
        return getLastSource(self.arguments, name);
    }

    /// Counts collected values without allocating a temporary slice.
    pub fn count_options(self: *const Parsed, name: []const u8) usize {
        return countEntries(self.options, name);
    }

    pub fn count_arguments(self: *const Parsed, name: []const u8) usize {
        return countEntries(self.arguments, name);
    }

    /// The returned slice belongs to the caller; any string values inside it
    /// still borrow from argv or the parser's configuration.
    pub fn get_all_options(
        self: *const Parsed,
        allocator: std.mem.Allocator,
        name: []const u8,
    ) ![]value.Value {
        return collectValues(allocator, self.options, name);
    }

    pub fn get_all_arguments(
        self: *const Parsed,
        allocator: std.mem.Allocator,
        name: []const u8,
    ) ![]value.Value {
        return collectValues(allocator, self.arguments, name);
    }
};

pub const HelpRequest = struct {
    command: *const command.Command,
    color_mode: color.ColorMode,
    no_color_env: bool,
};

pub const VersionRequest = struct {
    command: *const command.Command,
    color_mode: color.ColorMode,
    no_color_env: bool,
};

pub const Outcome = union(enum) {
    success: Parsed,
    help_requested: HelpRequest,
    version_requested: VersionRequest,
    invalid: @import("../diagnostic.zig").Diagnostic,
};

fn getLast(
    entries: []const value.Entry,
    name: []const u8,
) ?value.Value {
    const entry = getLastEntry(entries, name) orelse return null;
    return entry.value;
}

fn getLastSource(
    entries: []const value.Entry,
    name: []const u8,
) ?value.Source {
    const entry = getLastEntry(entries, name) orelse return null;
    return entry.source;
}

fn getLastEntry(
    entries: []const value.Entry,
    name: []const u8,
) ?value.Entry {
    var index = entries.len;
    while (index > 0) {
        index -= 1;
        if (std.mem.eql(u8, entries[index].name, name)) {
            return entries[index];
        }
    }
    return null;
}

fn countEntries(entries: []const value.Entry, name: []const u8) usize {
    var count: usize = 0;
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) count += 1;
    }
    return count;
}

fn collectValues(
    allocator: std.mem.Allocator,
    entries: []const value.Entry,
    name: []const u8,
) ![]value.Value {
    var count: usize = 0;
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) count += 1;
    }

    const result = try allocator.alloc(value.Value, count);
    var index: usize = 0;
    for (entries) |entry| {
        if (!std.mem.eql(u8, entry.name, name)) continue;
        result[index] = entry.value;
        index += 1;
    }
    return result;
}
