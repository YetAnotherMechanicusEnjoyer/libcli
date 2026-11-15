const std = @import("std");
const command = @import("../command.zig");
const color = @import("../color.zig");
const diagnostic = @import("../diagnostic.zig");
const value = @import("../value.zig");
const schema = @import("schema.zig");
const state_module = @import("state.zig");

const State = state_module.State;
const Flow = state_module.Flow;
const OptionMatch = schema.OptionMatch;
const Source = value.Source;
const Value = value.Value;
const Diagnostic = diagnostic.Diagnostic;

const BuiltinResult = union(enum) {
    unhandled,
    consumed,
    flow: Flow,
};

pub fn parseLong(
    state: *State,
    cmd: *const command.Command,
    args: []const []const u8,
    index: *usize,
    seen: []bool,
    token: []const u8,
) !?Flow {
    const body = token[2..];
    const equal_index = std.mem.indexOfScalar(u8, body, '=');
    const name = if (equal_index) |at| body[0..at] else body;
    const attached = if (equal_index) |at| body[at + 1 ..] else null;

    if (schema.findLongOption(cmd, name)) |matched| {
        if (try parseOption(
            state,
            cmd,
            args,
            index,
            seen,
            matched,
            attached,
            token,
        )) |issue| return .{ .invalid = issue };
        return null;
    }

    switch (try parseBuiltinLong(state, cmd, args, index, name, attached)) {
        .unhandled => {},
        .consumed => return null,
        .flow => |flow| return flow,
    }

    if (std.mem.startsWith(u8, name, "no-")) {
        if (schema.findLongOption(cmd, name[3..])) |matched| {
            if (matched.option.negatable) {
                if (attached != null) {
                    return .{ .invalid = .{
                        .kind = .unexpected_value,
                        .name = token,
                    } };
                }

                if (try storeOptionValue(
                    state,
                    cmd,
                    matched,
                    .{ .boolean = false },
                    .command_line,
                    seen,
                    token,
                )) |issue| return .{ .invalid = issue };
                return null;
            }
        }
    }

    return .{ .invalid = .{
        .kind = .unknown_option,
        .token = token,
    } };
}

fn parseBuiltinLong(
    state: *State,
    cmd: *const command.Command,
    args: []const []const u8,
    index: *usize,
    name: []const u8,
    attached: ?[]const u8,
) !BuiltinResult {
    if (std.mem.eql(u8, name, "help") and cmd.builtins.help) {
        if (attached != null) {
            return .{ .flow = .{ .invalid = .{
                .kind = .unexpected_value,
                .name = "--help",
            } } };
        }
        return .{ .flow = .{ .help = cmd } };
    }

    if (std.mem.eql(u8, name, "version") and
        cmd.builtins.version and cmd.version != null)
    {
        if (attached != null) {
            return .{ .flow = .{ .invalid = .{
                .kind = .unexpected_value,
                .name = "--version",
            } } };
        }
        return .{ .flow = .{ .version = cmd } };
    }

    if (std.mem.eql(u8, name, "no-color") and cmd.builtins.color) {
        if (attached != null) {
            return .{ .flow = .{ .invalid = .{
                .kind = .unexpected_value,
                .name = "--no-color",
            } } };
        }
        state.color_mode = .never;
        return .consumed;
    }

    if (std.mem.eql(u8, name, "color") and cmd.builtins.color) {
        const raw = attached orelse blk: {
            if (index.* + 1 >= args.len) {
                return .{ .flow = .{ .invalid = .{
                    .kind = .missing_value,
                    .name = "--color",
                } } };
            }
            index.* += 1;
            break :blk args[index.*];
        };

        state.color_mode = color.parse(raw) catch {
            return .{ .flow = .{ .invalid = .{
                .kind = .invalid_color,
                .token = raw,
                .name = "color",
                .expected = "auto, always, or never",
            } } };
        };
        return .consumed;
    }

    return .unhandled;
}

pub fn parseShort(
    state: *State,
    cmd: *const command.Command,
    args: []const []const u8,
    index: *usize,
    seen: []bool,
    token: []const u8,
) !?Flow {
    var offset: usize = 1;

    while (offset < token.len) : (offset += 1) {
        const short = token[offset];

        if (schema.findShortOption(cmd, short)) |matched| {
            if (matched.option.kind == null) {
                if (try storeOptionValue(
                    state,
                    cmd,
                    matched,
                    .{ .boolean = true },
                    .command_line,
                    seen,
                    token,
                )) |issue| return .{ .invalid = issue };
                continue;
            }

            const tail = token[offset + 1 ..];
            const raw = if (tail.len > 0) blk: {
                break :blk if (tail[0] == '=') tail[1..] else tail;
            } else blk: {
                if (index.* + 1 >= args.len) {
                    return .{ .invalid = .{
                        .kind = .missing_value,
                        .name = token[offset .. offset + 1],
                    } };
                }
                index.* += 1;
                break :blk args[index.*];
            };

            if (try parseAndStoreOption(
                state,
                cmd,
                matched,
                raw,
                seen,
                token,
            )) |issue| return .{ .invalid = issue };
            return null;
        }

        if (short == 'h' and cmd.builtins.help and
            !schema.hasShortOption(cmd, 'h') and
            !schema.hasLongOption(cmd, "help"))
        {
            return .{ .help = cmd };
        }

        if (short == 'V' and cmd.builtins.version and
            cmd.version != null and
            !schema.hasShortOption(cmd, 'V') and
            !schema.hasLongOption(cmd, "version"))
        {
            return .{ .version = cmd };
        }

        return .{ .invalid = .{
            .kind = .unknown_option,
            .token = token,
            .name = token[offset .. offset + 1],
        } };
    }

    return null;
}

fn parseOption(
    state: *State,
    cmd: *const command.Command,
    args: []const []const u8,
    index: *usize,
    seen: []bool,
    matched: OptionMatch,
    attached: ?[]const u8,
    token: []const u8,
) !?Diagnostic {
    if (matched.option.kind == null) {
        if (attached != null) {
            return .{
                .kind = .unexpected_value,
                .name = token,
            };
        }

        return try storeOptionValue(
            state,
            cmd,
            matched,
            .{ .boolean = true },
            .command_line,
            seen,
            token,
        );
    }

    const raw = attached orelse blk: {
        if (index.* + 1 >= args.len) {
            return .{
                .kind = .missing_value,
                .name = token,
            };
        }
        index.* += 1;
        break :blk args[index.*];
    };

    return try parseAndStoreOption(
        state,
        cmd,
        matched,
        raw,
        seen,
        token,
    );
}

fn parseAndStoreOption(
    state: *State,
    cmd: *const command.Command,
    matched: OptionMatch,
    raw: []const u8,
    seen: []bool,
    token: []const u8,
) !?Diagnostic {
    const kind = matched.option.kind orelse .boolean;
    const parsed = value.parse(kind, raw) catch {
        return .{
            .kind = .invalid_value,
            .token = raw,
            .name = token,
            .expected = schema.kindName(kind),
        };
    };

    return try storeOptionValue(
        state,
        cmd,
        matched,
        parsed,
        .command_line,
        seen,
        token,
    );
}

pub fn storeOptionValue(
    state: *State,
    cmd: *const command.Command,
    matched: OptionMatch,
    parsed: Value,
    source: Source,
    seen: []bool,
    token: []const u8,
) !?Diagnostic {
    const option = matched.option;

    if (seen[matched.index] and option.repeat == .reject) {
        return .{
            .kind = .duplicate_option,
            .token = token,
            .name = option.long,
        };
    }

    if (seen[matched.index] and option.repeat == .last_wins) {
        var item_index = state.options.items.len;
        while (item_index > 0) {
            item_index -= 1;
            const item = &state.options.items[item_index];
            if (item.owner == cmd and
                std.mem.eql(u8, item.name, option.long))
            {
                item.value = parsed;
                item.source = source;
                seen[matched.index] = true;
                return null;
            }
        }
    }

    try state.options.append(state.allocator, .{
        .name = option.long,
        .value = parsed,
        .source = source,
        .owner = cmd,
    });
    seen[matched.index] = true;
    return null;
}
