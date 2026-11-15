const command_def = @import("../command.zig");
const diagnostic = @import("../diagnostic.zig");
const value = @import("../value.zig");
const schema = @import("schema.zig");
const options = @import("options.zig");
const state_module = @import("state.zig");

const State = state_module.State;
const Diagnostic = diagnostic.Diagnostic;

/// Applies environment/default values, then checks required fields.
pub fn finishCommand(
    state: *State,
    cmd: *const command_def.Command,
    seen: []bool,
    positional_counts: []const usize,
) !?Diagnostic {
    for (cmd.options, 0..) |option, option_index| {
        if (!seen[option_index]) {
            if (option.env) |env_name| {
                if (schema.findEnvironment(state.environment, env_name)) |raw| {
                    const kind = option.kind orelse .boolean;
                    const parsed = value.parse(kind, raw) catch {
                        return .{
                            .kind = .invalid_environment,
                            .token = raw,
                            .name = option.long,
                            .expected = env_name,
                        };
                    };

                    if (try options.storeOptionValue(
                        state,
                        cmd,
                        .{ .option = &option, .index = option_index },
                        parsed,
                        .environment,
                        seen,
                        env_name,
                    )) |issue| return issue;
                }
            }
        }

        if (!seen[option_index]) {
            if (option.default) |raw| {
                const kind = option.kind orelse .boolean;
                const parsed = value.parse(kind, raw) catch {
                    return .{
                        .kind = .invalid_default,
                        .token = raw,
                        .name = option.long,
                    };
                };

                if (try options.storeOptionValue(
                    state,
                    cmd,
                    .{ .option = &option, .index = option_index },
                    parsed,
                    .default,
                    seen,
                    raw,
                )) |issue| return issue;
            }
        }

        if (option.required and !seen[option_index]) {
            return .{
                .kind = .missing_required_option,
                .name = option.long,
            };
        }

        if (option.kind == null and !seen[option_index]) {
            try state.options.append(state.allocator, .{
                .name = option.long,
                .value = .{ .boolean = false },
                .source = .implicit,
                .owner = cmd,
            });
        }
    }

    for (cmd.arguments, 0..) |argument, index| {
        if (argument.required and positional_counts[index] == 0) {
            return .{
                .kind = .missing_required_argument,
                .name = argument.name,
            };
        }
    }

    return null;
}
