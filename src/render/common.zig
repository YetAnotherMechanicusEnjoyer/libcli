const std = @import("std");
const command = @import("../command.zig");
const buffer = @import("buffer.zig");
const style = @import("style.zig");

const Command = command.Command;
const Option = command.Option;
const Argument = command.Argument;
const ValueKind = command.ValueKind;
const Buffer = buffer.Buffer;

pub const WrapState = struct {
    column: usize,
    indent: usize,
    width: usize,
    first: bool = true,
};

pub fn kindName(kind: ValueKind) []const u8 {
    return switch (kind) {
        .boolean => "BOOLEAN",
        .integer => "INTEGER",
        .float => "FLOAT",
        .string => "VALUE",
    };
}

pub fn optionMetavar(option: Option) []const u8 {
    if (option.metavar) |metavar| {
        if (metavar.len > 0) return metavar;
    }
    return kindName(option.kind orelse .string);
}

pub fn hasLongOption(cmd: *const Command, name: []const u8) bool {
    for (cmd.options) |option| {
        if (std.mem.eql(u8, option.long, name)) return true;
    }
    return false;
}

pub fn hasShortOption(cmd: *const Command, short: u8) bool {
    for (cmd.options) |option| {
        if (option.short) |candidate| {
            if (candidate == short) return true;
        }
    }
    return false;
}

pub fn visibleOptions(cmd: *const Command, show_hidden: bool) usize {
    var count: usize = 0;
    for (cmd.options) |option| {
        if (option.hidden and !show_hidden) continue;
        count += 1;
    }
    return count;
}

pub fn visibleArguments(cmd: *const Command, show_hidden: bool) usize {
    var count: usize = 0;
    for (cmd.arguments) |argument| {
        if (argument.hidden and !show_hidden) continue;
        count += 1;
    }
    return count;
}

pub fn visibleCommands(cmd: *const Command, show_hidden: bool) usize {
    var count: usize = 0;
    for (cmd.sub_commands) |sub_command| {
        if (sub_command.hidden and !show_hidden) continue;
        count += 1;
    }
    return count;
}

pub fn hasBuiltinOptions(cmd: *const Command) bool {
    return cmd.builtins.help or
        (cmd.builtins.version and cmd.version != null) or
        cmd.builtins.color;
}

pub fn optionLabelLength(option: Option) usize {
    var length = option.long.len + 2;
    if (option.short != null) length += 4;
    if (option.kind != null) length += 3 + optionMetavar(option).len;
    return length;
}

pub fn buildOptionLabel(
    allocator: std.mem.Allocator,
    option: Option,
) ![]u8 {
    var result = Buffer.init(allocator);
    errdefer result.deinit();

    if (option.short) |short| {
        try result.appendFmt("-{c}, ", .{short});
    }
    try result.appendFmt("--{s}", .{option.long});

    if (option.kind != null) {
        try result.appendFmt(" <{s}>", .{optionMetavar(option)});
    }
    return try result.toOwnedSlice();
}

pub fn buildArgumentLabel(
    allocator: std.mem.Allocator,
    argument: Argument,
) ![]u8 {
    var result = Buffer.init(allocator);
    errdefer result.deinit();

    try result.append(if (argument.required) "<" else "[");
    try result.append(argument.name);
    if (argument.variadic) try result.append("...");
    try result.append(if (argument.required) ">" else "]");

    return try result.toOwnedSlice();
}

fn appendAnnotation(
    result: *Buffer,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    if (result.data.items.len > 0) try result.append(" ");
    try result.appendFmt(fmt, args);
}

pub fn buildOptionMeta(
    allocator: std.mem.Allocator,
    option: Option,
    show_defaults: bool,
    show_env: bool,
) ![]u8 {
    var result = Buffer.init(allocator);
    errdefer result.deinit();

    if (option.required) {
        try appendAnnotation(&result, "(required)", .{});
    }

    if (show_defaults) {
        if (option.default) |default| {
            if ((option.kind orelse .boolean) == .string) {
                try appendAnnotation(
                    &result,
                    "(default: \"{s}\")",
                    .{default},
                );
            } else {
                try appendAnnotation(
                    &result,
                    "(default: {s})",
                    .{default},
                );
            }
        }
    }

    if (show_env) {
        if (option.env) |env| {
            try appendAnnotation(&result, "(env: {s})", .{env});
        }
    }

    return try result.toOwnedSlice();
}

pub fn buildArgumentMeta(
    allocator: std.mem.Allocator,
    argument: Argument,
) ![]u8 {
    var result = Buffer.init(allocator);
    errdefer result.deinit();

    if (argument.kind != .string) {
        try appendAnnotation(
            &result,
            "(type: {s})",
            .{kindName(argument.kind)},
        );
    }

    return try result.toOwnedSlice();
}

pub fn appendWords(
    result: *Buffer,
    text: []const u8,
    dim: bool,
    colored: bool,
    state: *WrapState,
) !void {
    var words = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (words.next()) |word| {
        const separator: usize = if (state.first) 0 else 1;
        if (!state.first and state.column + separator + word.len > state.width) {
            try result.append("\n");
            try result.appendSpaces(state.indent);
            state.column = state.indent;
            state.first = true;
        }

        if (!state.first) {
            try result.append(" ");
            state.column += 1;
        }

        if (dim and colored) try result.append(style.Style.dim);
        try result.append(word);
        if (dim and colored) try result.append(style.Style.reset);

        state.column += word.len;
        state.first = false;
    }
}

pub fn appendEntry(
    result: *Buffer,
    label: []const u8,
    help: []const u8,
    meta: []const u8,
    description_column: usize,
    width: usize,
    colored: bool,
) !void {
    try result.append("   ");
    if (colored) try result.append(style.Style.bold);
    try result.append(label);
    if (colored) try result.append(style.Style.reset);

    if (help.len == 0 and meta.len == 0) {
        try result.append("\n");
        return;
    }

    const label_end = 3 + label.len;
    const stacked = description_column <= label_end;
    var state: WrapState = undefined;

    if (stacked) {
        try result.append("\n");
        try result.appendSpaces(6);
        state = .{
            .column = 6,
            .indent = 6,
            .width = width,
        };
    } else {
        try result.appendSpaces(description_column - label_end);
        state = .{
            .column = description_column,
            .indent = description_column,
            .width = width,
        };
    }

    try appendWords(result, help, false, colored, &state);
    try appendWords(result, meta, true, colored, &state);
    try result.append("\n");
}

pub fn descriptionColumn(max_label: usize, width: usize) usize {
    const desired = 3 + max_label + 2;
    if (desired > width - 16) return 6;
    return @max(desired, 28);
}

pub fn appendSection(
    result: *Buffer,
    name: []const u8,
    colored: bool,
) !void {
    if (colored) try result.append(style.Style.dim);
    try result.append(":: ");
    if (colored) try result.append(style.Style.blue);
    try result.append(name);
    if (colored) try result.append(style.Style.dim);
    try result.append(":");
    if (colored) try result.append(style.Style.reset);
    try result.append("\n");
}

pub fn appendBuiltin(
    result: *Buffer,
    short: ?u8,
    long: []const u8,
    help: []const u8,
    description_column: usize,
    width: usize,
    colored: bool,
) !void {
    var label = Buffer.init(result.allocator);
    defer label.deinit();

    if (short) |value| try label.appendFmt("-{c}, ", .{value});
    try label.append(long);

    try appendEntry(
        result,
        label.data.items,
        help,
        "",
        description_column,
        width,
        colored,
    );
}
