const std = @import("std");
const command = @import("../command.zig");
const color = @import("../color.zig");
const diagnostic = @import("../diagnostic.zig");
const parser = @import("../parser.zig");
const value = @import("../value.zig");

const Command = command.Command;

test "parses options and positional arguments" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .options = &.{
            .{ .long = "output", .short = 'o', .kind = .string },
            .{ .long = "verbose", .short = 'v' },
            .{ .long = "count", .kind = .integer },
        },
        .arguments = &.{.{ .name = "INPUT", .required = true }},
    };
    const args = [_][]const u8{
        "-v",
        "--output=result.json",
        "--count",
        "3",
        "input.yaml",
    };

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expect(parsed.get_bool("verbose").?);
            try std.testing.expectEqualStrings(
                "result.json",
                parsed.get_string("output").?,
            );
            try std.testing.expectEqual(@as(i64, 3), parsed.get_int("count").?);
            try std.testing.expectEqualStrings(
                "input.yaml",
                parsed.get_argument_string("INPUT").?,
            );
        },
        else => return error.ExpectedSuccess,
    }
}

test "supports short bundles and attached short values" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .options = &.{
            .{ .long = "all", .short = 'a' },
            .{ .long = "verbose", .short = 'v' },
            .{ .long = "output", .short = 'o', .kind = .string },
        },
    };
    const args = [_][]const u8{"-avoresult.txt"};

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expect(parsed.get_bool("all").?);
            try std.testing.expect(parsed.get_bool("verbose").?);
            try std.testing.expectEqualStrings(
                "result.txt",
                parsed.get_string("output").?,
            );
        },
        else => return error.ExpectedSuccess,
    }
}

test "environment overrides defaults and CLI overrides environment" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .options = &.{.{
            .long = "output",
            .kind = .string,
            .default = "default.txt",
            .env = "DEMO_OUTPUT",
        }},
    };
    const environment = [_]parser.EnvironmentVariable{
        .{ .name = "DEMO_OUTPUT", .value = "environment.txt" },
    };
    const args = [_][]const u8{"--output=cli.txt"};

    var outcome = try parser.parse(allocator, &app, &args, .{
        .environment = &environment,
    });
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expectEqualStrings(
                "cli.txt",
                parsed.get_string("output").?,
            );
            try std.testing.expectEqual(
                value.Source.command_line,
                parsed.get_option_source("output").?,
            );
        },
        else => return error.ExpectedSuccess,
    }
}

test "uses environment values when the option is absent" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .options = &.{.{
            .long = "output",
            .kind = .string,
            .default = "default.txt",
            .env = "DEMO_OUTPUT",
        }},
    };
    const environment = [_]parser.EnvironmentVariable{
        .{ .name = "DEMO_OUTPUT", .value = "environment.txt" },
    };
    const args = [_][]const u8{};

    var outcome = try parser.parse(allocator, &app, &args, .{
        .environment = &environment,
    });
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expectEqualStrings(
                "environment.txt",
                parsed.get_string("output").?,
            );
            try std.testing.expectEqual(
                value.Source.environment,
                parsed.get_option_source("output").?,
            );
        },
        else => return error.ExpectedSuccess,
    }
}

test "parses built-in color controls in argument order" {
    const allocator = std.testing.allocator;
    const app = Command{ .name = "demo" };
    const args = [_][]const u8{
        "--no-color",
        "--color=always",
        "--no-color",
    };

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expectEqual(color.ColorMode.never, parsed.color_mode);
        },
        else => return error.ExpectedSuccess,
    }
}

test "returns help and version requests without treating them as errors" {
    const allocator = std.testing.allocator;
    const app = Command{ .name = "demo", .version = "1.2.3" };

    const help_args = [_][]const u8{"--help"};
    const help = try parser.parse(allocator, &app, &help_args, .{});
    try std.testing.expect(help == .help_requested);

    const version_args = [_][]const u8{"-V"};
    const version = try parser.parse(allocator, &app, &version_args, .{});
    try std.testing.expect(version == .version_requested);
}

test "reports missing required options and arguments" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .options = &.{.{ .long = "format", .kind = .string, .required = true }},
        .arguments = &.{.{ .name = "INPUT", .required = true }},
    };
    const args = [_][]const u8{};

    const outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .invalid => |issue| {
            try std.testing.expectEqual(
                diagnostic.Kind.missing_required_option,
                issue.kind,
            );
        },
        else => return error.ExpectedDiagnostic,
    }
}

test "collects repeatable options" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .options = &.{.{
            .long = "include",
            .kind = .string,
            .repeat = .collect,
        }},
    };
    const args = [_][]const u8{
        "--include=images",
        "--include",
        "documents",
    };

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            const all = try parsed.get_all_options(allocator, "include");
            defer allocator.free(all);
            try std.testing.expectEqual(@as(usize, 2), all.len);
            try std.testing.expectEqualStrings("images", all[0].string);
            try std.testing.expectEqualStrings("documents", all[1].string);
        },
        else => return error.ExpectedSuccess,
    }
}

test "resolves subcommands" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .sub_commands = &.{.{
            .name = "inspect",
            .options = &.{.{ .long = "json" }},
            .arguments = &.{.{ .name = "INPUT", .required = true }},
        }},
    };
    const args = [_][]const u8{ "inspect", "--json", "file.txt" };

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expectEqualStrings("inspect", parsed.command.name);
            try std.testing.expect(parsed.get_bool("json").?);
            try std.testing.expectEqualStrings(
                "file.txt",
                parsed.get_argument_string("INPUT").?,
            );
        },
        else => return error.ExpectedSuccess,
    }
}

test "negatable options accept --no-name" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .options = &.{.{
            .long = "cache",
            .negatable = true,
            .default = "true",
        }},
    };
    const args = [_][]const u8{"--no-cache"};

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expect(!parsed.get_bool("cache").?);
        },
        else => return error.ExpectedSuccess,
    }
}

test "help request retains the selected color mode" {
    const allocator = std.testing.allocator;
    const app = Command{ .name = "demo" };
    const args = [_][]const u8{ "--color=never", "--help" };

    const outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .help_requested => |request| {
            try std.testing.expectEqual(color.ColorMode.never, request.color_mode);
        },
        else => return error.ExpectedHelp,
    }
}

test "double dash ends option parsing" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .arguments = &.{.{ .name = "INPUT", .required = true }},
    };
    const args = [_][]const u8{ "--", "-input.txt" };

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expectEqualStrings(
                "-input.txt",
                parsed.get_argument_string("INPUT").?,
            );
        },
        else => return error.ExpectedSuccess,
    }
}

test "NO_COLOR is propagated to help rendering" {
    const allocator = std.testing.allocator;
    const app = Command{ .name = "demo" };
    const environment = [_]parser.EnvironmentVariable{
        .{ .name = "NO_COLOR", .value = "1" },
    };
    const args = [_][]const u8{"--help"};

    const outcome = try parser.parse(allocator, &app, &args, .{
        .environment = &environment,
    });
    switch (outcome) {
        .help_requested => |request| {
            try std.testing.expect(request.no_color_env);
        },
        else => return error.ExpectedHelp,
    }
}

test "accepts negative numeric positional values" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .arguments = &.{.{
            .name = "OFFSET",
            .kind = .integer,
            .required = true,
        }},
    };
    const args = [_][]const u8{"-42"};

    var outcome = try parser.parse(allocator, &app, &args, .{});
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            try std.testing.expectEqual(
                @as(i64, -42),
                parsed.get_argument_int("OFFSET").?,
            );
        },
        else => return error.ExpectedSuccess,
    }
}
