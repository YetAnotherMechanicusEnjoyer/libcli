const std = @import("std");
const command = @import("../command.zig");
const buffer = @import("buffer.zig");
const common = @import("common.zig");

const Command = command.Command;
const Buffer = buffer.Buffer;

/// Render the compact command syntax, without section headings.
pub fn render(
    allocator: std.mem.Allocator,
    cmd: *const Command,
) ![]u8 {
    var result = Buffer.init(allocator);
    errdefer result.deinit();

    try result.append(cmd.name);

    if (common.visibleOptions(cmd, false) > 0 or
        common.hasBuiltinOptions(cmd))
    {
        try result.append(" [OPTIONS]");
    }

    for (cmd.arguments) |argument| {
        if (argument.hidden) continue;
        const label = try common.buildArgumentLabel(allocator, argument);
        defer allocator.free(label);
        try result.append(" ");
        try result.append(label);
    }

    if (common.visibleCommands(cmd, false) > 0) {
        try result.append(" [COMMAND]");
    }

    return try result.toOwnedSlice();
}
