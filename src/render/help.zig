const std = @import("std");
const command = @import("../command.zig");
const options = @import("options.zig");
const buffer = @import("buffer.zig");
const common = @import("common.zig");
const style = @import("style.zig");
const usage = @import("usage.zig");

const Command = command.Command;
const HelpOptions = options.HelpOptions;
const Buffer = buffer.Buffer;
const WrapState = common.WrapState;

/// Render a complete help document.
pub fn render(
    io: std.Io,
    allocator: std.mem.Allocator,
    cmd: *const Command,
    settings: HelpOptions,
) ![]u8 {
    var result = Buffer.init(allocator);
    errdefer result.deinit();

    const width = @max(settings.width, 40);
    const colored = style.colorsEnabled(
        io,
        settings.color,
        settings.no_color_env,
    );

    try renderUsage(&result, allocator, cmd, width, colored);
    try renderDescription(&result, cmd, width, colored);
    try renderArguments(&result, allocator, cmd, settings, width, colored);
    try renderOptions(&result, allocator, cmd, settings, width, colored);
    try renderCommands(&result, cmd, settings, width, colored);
    try renderExamples(&result, cmd, width, colored);

    return try result.toOwnedSlice();
}

fn renderUsage(
    result: *Buffer,
    allocator: std.mem.Allocator,
    cmd: *const Command,
    width: usize,
    colored: bool,
) !void {
    try common.appendSection(result, "Usage", colored);

    const syntax = try usage.render(allocator, cmd);
    defer allocator.free(syntax);

    try result.append("   ");
    if (colored) try result.append(style.Style.green);
    try result.append(cmd.name);
    if (colored) try result.append(style.Style.reset);

    var state = WrapState{
        .column = 3 + cmd.name.len,
        .indent = 3,
        .width = width,
        .first = false,
    };
    try common.appendWords(
        result,
        syntax[cmd.name.len..],
        false,
        false,
        &state,
    );
    try result.append("\n");
}

fn renderDescription(
    result: *Buffer,
    cmd: *const Command,
    width: usize,
    colored: bool,
) !void {
    if (cmd.description.len == 0) return;

    try result.append("\n");
    try common.appendSection(result, "Description", colored);
    try result.append("   ");

    var state = WrapState{
        .column = 3,
        .indent = 3,
        .width = width,
    };
    try common.appendWords(
        result,
        cmd.description,
        false,
        false,
        &state,
    );
    try result.append("\n");
}

fn renderArguments(
    result: *Buffer,
    allocator: std.mem.Allocator,
    cmd: *const Command,
    settings: HelpOptions,
    width: usize,
    colored: bool,
) !void {
    if (common.visibleArguments(cmd, settings.show_hidden) == 0) return;

    var max_label: usize = 0;
    for (cmd.arguments) |argument| {
        if (argument.hidden and !settings.show_hidden) continue;
        const label = try common.buildArgumentLabel(allocator, argument);
        defer allocator.free(label);
        max_label = @max(max_label, label.len);
    }

    try result.append("\n");
    try common.appendSection(result, "Arguments", colored);
    const column = common.descriptionColumn(max_label, width);

    for (cmd.arguments) |argument| {
        if (argument.hidden and !settings.show_hidden) continue;

        const label = try common.buildArgumentLabel(allocator, argument);
        defer allocator.free(label);
        const meta = try common.buildArgumentMeta(allocator, argument);
        defer allocator.free(meta);

        try common.appendEntry(
            result,
            label,
            argument.help,
            meta,
            column,
            width,
            colored,
        );
    }
}

fn renderOptions(
    result: *Buffer,
    allocator: std.mem.Allocator,
    cmd: *const Command,
    settings: HelpOptions,
    width: usize,
    colored: bool,
) !void {
    const builtin_count = countBuiltins(cmd);
    if (common.visibleOptions(cmd, settings.show_hidden) == 0 and
        builtin_count == 0) return;

    const max_label = maximumOptionLabel(cmd, settings);
    const column = common.descriptionColumn(max_label, width);

    try result.append("\n");
    try common.appendSection(result, "Options", colored);

    try renderHelpBuiltin(result, cmd, column, width, colored);
    try renderVersionBuiltin(result, cmd, column, width, colored);
    try renderUserOptions(result, allocator, cmd, settings, column, width, colored);
    try renderColorBuiltins(result, cmd, column, width, colored);
}

fn renderHelpBuiltin(
    result: *Buffer,
    cmd: *const Command,
    column: usize,
    width: usize,
    colored: bool,
) !void {
    if (!cmd.builtins.help or common.hasLongOption(cmd, "help")) return;

    const short: ?u8 = if (common.hasShortOption(cmd, 'h')) null else 'h';
    try common.appendBuiltin(
        result,
        short,
        "--help",
        "Display this help message.",
        column,
        width,
        colored,
    );
}

fn renderVersionBuiltin(
    result: *Buffer,
    cmd: *const Command,
    column: usize,
    width: usize,
    colored: bool,
) !void {
    if (!cmd.builtins.version or cmd.version == null or
        common.hasLongOption(cmd, "version")) return;

    const short: ?u8 = if (common.hasShortOption(cmd, 'V')) null else 'V';
    try common.appendBuiltin(
        result,
        short,
        "--version",
        "Display version information.",
        column,
        width,
        colored,
    );
}

fn renderUserOptions(
    result: *Buffer,
    allocator: std.mem.Allocator,
    cmd: *const Command,
    settings: HelpOptions,
    column: usize,
    width: usize,
    colored: bool,
) !void {
    for (cmd.options) |option| {
        if (option.hidden and !settings.show_hidden) continue;

        const label = try common.buildOptionLabel(allocator, option);
        defer allocator.free(label);
        const meta = try common.buildOptionMeta(
            allocator,
            option,
            settings.show_defaults,
            settings.show_env,
        );
        defer allocator.free(meta);

        try common.appendEntry(
            result,
            label,
            option.help,
            meta,
            column,
            width,
            colored,
        );
    }
}

fn renderColorBuiltins(
    result: *Buffer,
    cmd: *const Command,
    column: usize,
    width: usize,
    colored: bool,
) !void {
    if (!cmd.builtins.color) return;

    if (!common.hasLongOption(cmd, "color")) {
        try common.appendEntry(
            result,
            "--color=WHEN",
            "Set when to use colors: auto, always, or never.",
            "(default: auto)",
            column,
            width,
            colored,
        );
    }

    if (!common.hasLongOption(cmd, "no-color")) {
        try common.appendEntry(
            result,
            "--no-color",
            "Disable colored output (equivalent to --color=never).",
            "",
            column,
            width,
            colored,
        );
    }
}

fn renderCommands(
    result: *Buffer,
    cmd: *const Command,
    settings: HelpOptions,
    width: usize,
    colored: bool,
) !void {
    if (common.visibleCommands(cmd, settings.show_hidden) == 0) return;

    var max_label: usize = 0;
    for (cmd.sub_commands) |sub_command| {
        if (sub_command.hidden and !settings.show_hidden) continue;
        max_label = @max(max_label, sub_command.name.len);
    }

    try result.append("\n");
    try common.appendSection(result, "Commands", colored);
    const column = common.descriptionColumn(max_label, width);

    for (cmd.sub_commands) |sub_command| {
        if (sub_command.hidden and !settings.show_hidden) continue;
        try common.appendEntry(
            result,
            sub_command.name,
            sub_command.description,
            "",
            column,
            width,
            colored,
        );
    }
}

fn renderExamples(
    result: *Buffer,
    cmd: *const Command,
    width: usize,
    colored: bool,
) !void {
    if (cmd.examples.len == 0) return;

    try result.append("\n");
    try common.appendSection(result, "Examples", colored);

    for (cmd.examples) |example| {
        try common.appendEntry(
            result,
            example.command,
            example.description,
            "",
            28,
            width,
            colored,
        );
    }
}

fn countBuiltins(cmd: *const Command) usize {
    return @as(usize, @intFromBool(
        cmd.builtins.help and !common.hasLongOption(cmd, "help"),
    )) +
        @as(usize, @intFromBool(
            cmd.builtins.version and cmd.version != null and
                !common.hasLongOption(cmd, "version"),
        )) +
        @as(usize, @intFromBool(
            cmd.builtins.color and !common.hasLongOption(cmd, "color"),
        )) +
        @as(usize, @intFromBool(
            cmd.builtins.color and !common.hasLongOption(cmd, "no-color"),
        ));
}

fn maximumOptionLabel(cmd: *const Command, settings: HelpOptions) usize {
    var max_label: usize = 0;
    for (cmd.options) |option| {
        if (option.hidden and !settings.show_hidden) continue;
        max_label = @max(max_label, common.optionLabelLength(option));
    }

    if (cmd.builtins.help and !common.hasLongOption(cmd, "help")) {
        const short: usize = if (common.hasShortOption(cmd, 'h')) 0 else 4;
        max_label = @max(max_label, "--help".len + short);
    }

    if (cmd.builtins.version and cmd.version != null and
        !common.hasLongOption(cmd, "version"))
    {
        const short: usize = if (common.hasShortOption(cmd, 'V')) 0 else 4;
        max_label = @max(max_label, "--version".len + short);
    }

    if (cmd.builtins.color) {
        if (!common.hasLongOption(cmd, "color")) {
            max_label = @max(max_label, "--color=WHEN".len);
        }
        if (!common.hasLongOption(cmd, "no-color")) {
            max_label = @max(max_label, "--no-color".len);
        }
    }

    return max_label;
}

test "help rendering contains aligned sections and builtin color controls" {
    const allocator = std.testing.allocator;
    const app = Command{
        .name = "demo",
        .description = "A small demonstration tool.",
        .version = "1.0.0",
        .options = &.{.{
            .long = "output",
            .short = 'o',
            .kind = .string,
            .metavar = "PATH",
            .help = "Write output to this path.",
            .default = "result.txt",
        }},
        .arguments = &.{.{
            .name = "INPUT",
            .required = true,
            .help = "Input file.",
        }},
    };

    const rendered = try render(undefined, allocator, &app, .{
        .color = .never,
    });
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, ":: Usage:") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, ":: Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "--color=WHEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "default: \"result.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[") == null);
}
