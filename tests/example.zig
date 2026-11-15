const std = @import("std");
const cli = @import("cli");

const app = cli.Command{
    .name = "convertor",
    .description = "A universal file conversion utility.",
    .version = "1.0.0",
    .options = &.{
        .{
            .long = "directory",
            .short = 'd',
            .kind = .string,
            .metavar = "PATH",
            .help = "In/Output root directory.",
            .default = "~/.local/share/convertor",
        },
        .{
            .long = "format",
            .short = 'f',
            .kind = .string,
            .metavar = "FORMAT",
            .help = "Output format.",
            .required = true,
            .env = "CONVERTOR_FORMAT",
        },
        .{
            .long = "force",
            .short = 'F',
            .help = "Overwrite existing files.",
        },
        .{
            .long = "include",
            .kind = .string,
            .metavar = "TYPE",
            .help = "Include an additional conversion type.",
            .repeat = .collect,
        },
    },
    .arguments = &.{
        .{
            .name = "INPUT",
            .help = "Input file to convert.",
            .required = true,
        },
        .{
            .name = "OUTPUT",
            .help = "Destination file.",
        },
    },
    .examples = &.{
        .{
            .command = "convertor -f json input.yaml output.json",
            .description = "Convert YAML to JSON.",
        },
    },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(allocator);

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    if (argv.len > 1) {
        for (argv[1..]) |argument| {
            try args.append(allocator, argument);
        }
    }

    var environment = std.ArrayList(cli.EnvironmentVariable).empty;
    defer environment.deinit(allocator);

    if (init.environ_map.get("NO_COLOR")) |raw| {
        try environment.append(allocator, .{
            .name = "NO_COLOR",
            .value = raw,
        });
    }
    if (init.environ_map.get("CONVERTOR_FORMAT")) |raw| {
        try environment.append(allocator, .{
            .name = "CONVERTOR_FORMAT",
            .value = raw,
        });
    }

    var outcome = try cli.parse(allocator, &app, args.items, .{
        .environment = environment.items,
    });
    switch (outcome) {
        .success => |*parsed| {
            defer parsed.deinit();
            const input = parsed.get_argument_string("INPUT") orelse "";
            const output = parsed.get_argument_string("OUTPUT") orelse "output";
            const format = parsed.get_string("format") orelse "";
            try std.Io.File.stdout().writeStreamingAll(
                init.io,
                try std.fmt.allocPrint(
                    allocator,
                    "input={s}\noutput={s}\nformat={s}\n",
                    .{ input, output, format },
                ),
            );
        },
        .help_requested => |request| {
            const help = try cli.render_help(
                init.io,
                allocator,
                request.command,
                .{
                    .color = request.color_mode,
                    .no_color_env = request.no_color_env,
                },
            );
            try std.Io.File.stdout().writeStreamingAll(init.io, help);
        },
        .version_requested => |request| {
            const cmd = request.command;
            const version = cmd.version orelse "";
            try std.Io.File.stdout().writeStreamingAll(
                init.io,
                try std.fmt.allocPrint(allocator, "{s} {s}\n", .{
                    cmd.name,
                    version,
                }),
            );
        },
        .invalid => |issue| {
            const message = try cli.render_diagnostic(allocator, issue);
            try std.Io.File.stderr().writeStreamingAll(
                init.io,
                try std.fmt.allocPrint(allocator, "error: {s}\n", .{message}),
            );
        },
    }
}
