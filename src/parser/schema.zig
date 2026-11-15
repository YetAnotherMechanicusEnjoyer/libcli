const std = @import("std");
const command = @import("../command.zig");
const diagnostic = @import("../diagnostic.zig");
const types = @import("types.zig");

pub const OptionMatch = struct {
    option: *const command.Option,
    index: usize,
};

pub fn validate(cmd: *const command.Command) ?diagnostic.Diagnostic {
    if (cmd.name.len == 0 or
        std.mem.startsWith(u8, cmd.name, "-") or
        containsWhitespace(cmd.name))
    {
        return .{
            .kind = .invalid_schema,
            .name = "command names must be non-empty and contain no whitespace or leading dash",
        };
    }

    for (cmd.options, 0..) |option, index| {
        if (option.long.len == 0 or
            std.mem.startsWith(u8, option.long, "-") or
            containsWhitespace(option.long))
        {
            return .{
                .kind = .invalid_schema,
                .name = "option names must be non-empty, contain no whitespace, and omit leading dashes",
            };
        }

        if (std.mem.indexOfScalar(u8, option.long, '=') != null) {
            return .{
                .kind = .invalid_schema,
                .name = "long option names must not contain '='",
            };
        }

        if (option.short) |short| {
            if (short < 0x21 or short > 0x7e or short == '-' or short == '=') {
                return .{
                    .kind = .invalid_schema,
                    .name = "short option names must be printable non-separator characters",
                };
            }
        }

        if (option.negatable and option.kind != null and
            option.kind.? != .boolean)
        {
            return .{
                .kind = .invalid_schema,
                .name = "only flag or boolean options can be negatable",
            };
        }

        for (cmd.options[index + 1 ..]) |other| {
            if (std.mem.eql(u8, option.long, other.long)) {
                return .{
                    .kind = .invalid_schema,
                    .name = "duplicate long option name",
                };
            }

            if (option.short != null and other.short != null and
                option.short.? == other.short.?)
            {
                return .{
                    .kind = .invalid_schema,
                    .name = "duplicate short option name",
                };
            }
        }
    }

    for (cmd.sub_commands, 0..) |sub_command, index| {
        if (sub_command.name.len == 0 or
            std.mem.startsWith(u8, sub_command.name, "-") or
            containsWhitespace(sub_command.name))
        {
            return .{
                .kind = .invalid_schema,
                .name = "subcommand names must be non-empty and contain no whitespace or leading dash",
            };
        }
        for (cmd.sub_commands[index + 1 ..]) |other| {
            if (std.mem.eql(u8, sub_command.name, other.name)) {
                return .{
                    .kind = .invalid_schema,
                    .name = "duplicate subcommand name",
                };
            }
        }

        if (validate(&sub_command)) |issue| return issue;
    }

    var optional_seen = false;
    for (cmd.arguments, 0..) |argument, index| {
        if (argument.name.len == 0 or containsWhitespace(argument.name)) {
            return .{
                .kind = .invalid_schema,
                .name = "argument names must be non-empty and contain no whitespace",
            };
        }

        for (cmd.arguments[index + 1 ..]) |other| {
            if (std.mem.eql(u8, argument.name, other.name)) {
                return .{
                    .kind = .invalid_schema,
                    .name = "duplicate positional argument name",
                };
            }
        }

        if (argument.variadic and index + 1 != cmd.arguments.len) {
            return .{
                .kind = .invalid_schema,
                .name = "a variadic positional argument must be last",
            };
        }

        if (!argument.required) optional_seen = true;
        if (argument.required and optional_seen) {
            return .{
                .kind = .invalid_schema,
                .name = "required positional arguments cannot follow optional ones",
            };
        }
    }

    return null;
}

fn containsWhitespace(text: []const u8) bool {
    for (text) |character| {
        if (std.ascii.isWhitespace(character)) return true;
    }
    return false;
}

pub fn findLongOption(
    cmd: *const command.Command,
    name: []const u8,
) ?OptionMatch {
    for (cmd.options, 0..) |*option, index| {
        if (std.mem.eql(u8, option.long, name)) {
            return .{ .option = option, .index = index };
        }
    }
    return null;
}

pub fn findShortOption(
    cmd: *const command.Command,
    short: u8,
) ?OptionMatch {
    for (cmd.options, 0..) |*option, index| {
        if (option.short) |candidate| {
            if (candidate == short) {
                return .{ .option = option, .index = index };
            }
        }
    }
    return null;
}

pub fn findSubcommand(
    cmd: *const command.Command,
    name: []const u8,
) ?*const command.Command {
    for (cmd.sub_commands) |*sub_command| {
        if (std.mem.eql(u8, sub_command.name, name)) return sub_command;
    }
    return null;
}

pub fn findEnvironment(
    environment: []const types.EnvironmentVariable,
    name: []const u8,
) ?[]const u8 {
    for (environment) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry.value;
    }
    return null;
}

pub fn hasLongOption(cmd: *const command.Command, name: []const u8) bool {
    return findLongOption(cmd, name) != null;
}

pub fn hasShortOption(cmd: *const command.Command, short: u8) bool {
    return findShortOption(cmd, short) != null;
}

pub fn isLongOption(token: []const u8) bool {
    return token.len > 2 and std.mem.startsWith(u8, token, "--");
}

pub fn isShortOption(token: []const u8) bool {
    return token.len > 1 and token[0] == '-' and token[1] != '-';
}

pub fn kindName(kind: command.ValueKind) []const u8 {
    return switch (kind) {
        .boolean => "BOOLEAN",
        .integer => "INTEGER",
        .float => "FLOAT",
        .string => "STRING",
    };
}
