const std = @import("std");
const command = @import("../command.zig");
const color = @import("../color.zig");
const diagnostic = @import("../diagnostic.zig");
const value = @import("../value.zig");
const types = @import("types.zig");

pub const Flow = union(enum) {
    complete,
    help: *const command.Command,
    version: *const command.Command,
    invalid: diagnostic.Diagnostic,
};

pub const State = struct {
    allocator: std.mem.Allocator,
    options: std.ArrayList(value.Entry) = .empty,
    arguments: std.ArrayList(value.Entry) = .empty,
    environment: []const types.EnvironmentVariable,
    color_mode: color.ColorMode,
    no_color_env: bool,
    selected_command: *const command.Command,

    pub fn deinit(self: *State) void {
        self.options.deinit(self.allocator);
        self.arguments.deinit(self.allocator);
    }

    pub fn finish(self: *State) !types.Parsed {
        const options = try self.options.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(options);
        const arguments = try self.arguments.toOwnedSlice(self.allocator);

        return .{
            .allocator = self.allocator,
            .command = self.selected_command,
            .options = options,
            .arguments = arguments,
            .color_mode = self.color_mode,
            .no_color_env = self.no_color_env,
        };
    }
};
