const std = @import("std");
const command = @import("../command.zig");
const value = @import("../value.zig");
const types = @import("types.zig");
const diagnostic = @import("../diagnostic.zig");
const state_module = @import("state.zig");
const schema = @import("schema.zig");
const options = @import("options.zig");
const finish = @import("finish.zig");

const State = state_module.State;
const Flow = state_module.Flow;
const Diagnostic = diagnostic.Diagnostic;

pub fn parse(
    allocator: std.mem.Allocator,
    root: *const command.Command,
    args: []const []const u8,
    settings: types.Options,
) !types.Outcome {
    if (schema.validate(root)) |issue| {
        return .{ .invalid = issue };
    }

    var state = State{
        .allocator = allocator,
        .environment = settings.environment,
        .color_mode = settings.color,
        .no_color_env = hasNoColorEnvironment(settings.environment),
        .selected_command = root,
    };
    defer state.deinit();

    const flow = try parseCommand(&state, root, args, 0);
    return switch (flow) {
        .complete => .{ .success = try state.finish() },
        .help => |cmd| .{ .help_requested = .{
            .command = cmd,
            .color_mode = state.color_mode,
            .no_color_env = state.no_color_env,
        } },
        .version => |cmd| .{ .version_requested = .{
            .command = cmd,
            .color_mode = state.color_mode,
            .no_color_env = state.no_color_env,
        } },
        .invalid => |issue| .{ .invalid = issue },
    };
}

fn parseCommand(
    state: *State,
    cmd: *const command.Command,
    args: []const []const u8,
    start: usize,
) !Flow {
    state.selected_command = cmd;

    const seen = try state.allocator.alloc(bool, cmd.options.len);
    defer state.allocator.free(seen);
    @memset(seen, false);

    const positional_counts = try state.allocator.alloc(usize, cmd.arguments.len);
    defer state.allocator.free(positional_counts);
    @memset(positional_counts, 0);

    var positional_index: usize = 0;
    var options_ended = false;
    var index = start;

    while (index < args.len) : (index += 1) {
        const token = args[index];

        if (!options_ended and std.mem.eql(u8, token, "--")) {
            options_ended = true;
            continue;
        }

        if (!options_ended and schema.isLongOption(token)) {
            if (try options.parseLong(
                state,
                cmd,
                args,
                &index,
                seen,
                token,
            )) |flow| return flow;
            continue;
        }

        if (!options_ended and schema.isShortOption(token) and
            !isNegativePositional(cmd, positional_index, token))
        {
            if (try options.parseShort(
                state,
                cmd,
                args,
                &index,
                seen,
                token,
            )) |flow| return flow;
            continue;
        }

        if (!options_ended) {
            if (schema.findSubcommand(cmd, token)) |sub_command| {
                if (try finish.finishCommand(
                    state,
                    cmd,
                    seen,
                    positional_counts,
                )) |issue| return .{ .invalid = issue };

                return try parseCommand(
                    state,
                    sub_command,
                    args,
                    index + 1,
                );
            }
        }

        if (try appendPositional(
            state,
            cmd,
            token,
            &positional_index,
            positional_counts,
        )) |issue| return .{ .invalid = issue };
    }

    if (try finish.finishCommand(state, cmd, seen, positional_counts)) |issue| {
        return .{ .invalid = issue };
    }
    return .complete;
}

fn appendPositional(
    state: *State,
    cmd: *const command.Command,
    token: []const u8,
    positional_index: *usize,
    counts: []usize,
) !?Diagnostic {
    while (positional_index.* < cmd.arguments.len and
        counts[positional_index.*] > 0 and
        !cmd.arguments[positional_index.*].variadic)
    {
        positional_index.* += 1;
    }

    if (positional_index.* >= cmd.arguments.len) {
        return .{
            .kind = if (cmd.sub_commands.len > 0)
                .unknown_subcommand
            else
                .too_many_arguments,
            .token = token,
        };
    }

    const argument = &cmd.arguments[positional_index.*];
    const parsed = value.parse(argument.kind, token) catch {
        return .{
            .kind = .invalid_value,
            .token = token,
            .name = argument.name,
            .expected = kindName(argument.kind),
        };
    };

    try state.arguments.append(state.allocator, .{
        .name = argument.name,
        .value = parsed,
        .source = .command_line,
        .owner = cmd,
    });
    counts[positional_index.*] += 1;

    if (!argument.variadic) positional_index.* += 1;
    return null;
}

fn kindName(kind: command.ValueKind) []const u8 {
    return switch (kind) {
        .boolean => "BOOLEAN",
        .integer => "INTEGER",
        .float => "FLOAT",
        .string => "STRING",
    };
}

fn hasNoColorEnvironment(
    environment: []const types.EnvironmentVariable,
) bool {
    for (environment) |entry| {
        if (std.mem.eql(u8, entry.name, "NO_COLOR")) {
            return entry.value.len > 0;
        }
    }
    return false;
}

fn isNegativePositional(
    cmd: *const command.Command,
    argument_index: usize,
    token: []const u8,
) bool {
    if (argument_index >= cmd.arguments.len or token.len < 2) return false;
    if (schema.findShortOption(cmd, token[1]) != null) return false;
    if (token[0] != '-') return false;

    return switch (cmd.arguments[argument_index].kind) {
        .integer => isInteger(token),
        .float => isFloat(token),
        else => false,
    };
}

fn isInteger(token: []const u8) bool {
    _ = std.fmt.parseInt(i64, token, 10) catch return false;
    return true;
}

fn isFloat(token: []const u8) bool {
    _ = std.fmt.parseFloat(f64, token) catch return false;
    return true;
}
