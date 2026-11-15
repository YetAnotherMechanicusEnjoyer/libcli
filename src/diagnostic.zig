const std = @import("std");

pub const Kind = enum {
    invalid_schema,
    unknown_option,
    unknown_subcommand,
    missing_value,
    unexpected_value,
    invalid_value,
    duplicate_option,
    missing_required_option,
    missing_required_argument,
    too_many_arguments,
    invalid_default,
    invalid_environment,
    invalid_color,
};

/// A structured parsing diagnostic. All strings are borrowed from the command
/// schema or the original argument slice; this structure owns no memory.
pub const Diagnostic = struct {
    kind: Kind,
    token: []const u8 = "",
    name: []const u8 = "",
    expected: []const u8 = "",
};

pub fn render(
    allocator: std.mem.Allocator,
    diagnostic: Diagnostic,
) ![]u8 {
    return switch (diagnostic.kind) {
        .invalid_schema => std.fmt.allocPrint(
            allocator,
            "invalid command definition: {s}",
            .{diagnostic.name},
        ),
        .unknown_option => std.fmt.allocPrint(
            allocator,
            "unknown option '{s}'",
            .{diagnostic.token},
        ),
        .unknown_subcommand => std.fmt.allocPrint(
            allocator,
            "unknown subcommand '{s}'",
            .{diagnostic.token},
        ),
        .missing_value => std.fmt.allocPrint(
            allocator,
            "missing value for '{s}'",
            .{diagnostic.name},
        ),
        .unexpected_value => std.fmt.allocPrint(
            allocator,
            "option '{s}' does not accept a value",
            .{diagnostic.name},
        ),
        .invalid_value => std.fmt.allocPrint(
            allocator,
            "invalid value '{s}' for '{s}' (expected {s})",
            .{ diagnostic.token, diagnostic.name, diagnostic.expected },
        ),
        .duplicate_option => std.fmt.allocPrint(
            allocator,
            "option '{s}' cannot be specified more than once",
            .{diagnostic.name},
        ),
        .missing_required_option => std.fmt.allocPrint(
            allocator,
            "missing required option '--{s}'",
            .{diagnostic.name},
        ),
        .missing_required_argument => std.fmt.allocPrint(
            allocator,
            "missing required argument '<{s}>'",
            .{diagnostic.name},
        ),
        .too_many_arguments => std.fmt.allocPrint(
            allocator,
            "unexpected positional argument '{s}'",
            .{diagnostic.token},
        ),
        .invalid_default => std.fmt.allocPrint(
            allocator,
            "invalid default value '{s}' for '--{s}'",
            .{ diagnostic.token, diagnostic.name },
        ),
        .invalid_environment => std.fmt.allocPrint(
            allocator,
            "invalid value from environment variable '{s}' for '--{s}'",
            .{ diagnostic.expected, diagnostic.name },
        ),
        .invalid_color => std.fmt.allocPrint(
            allocator,
            "invalid color mode '{s}' (expected auto, always, or never)",
            .{diagnostic.token},
        ),
    };
}
