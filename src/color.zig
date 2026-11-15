const std = @import("std");

/// Policy used to decide whether ANSI color sequences are emitted.
pub const ColorMode = enum {
    auto,
    always,
    never,
};

pub fn parse(value: []const u8) error{InvalidColorMode}!ColorMode {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "always")) return .always;
    if (std.mem.eql(u8, value, "never")) return .never;

    return error.InvalidColorMode;
}

/// Resolves a color mode for the given output stream.
/// `no_color_env` should be true when NO_COLOR is set to a non-empty value.
pub fn enabled(
    io: std.Io,
    mode: ColorMode,
    no_color_env: bool,
) bool {
    return switch (mode) {
        .always => true,
        .never => false,
        .auto => detectTerminal(io, no_color_env),
    };
}

fn detectTerminal(io: std.Io, no_color_env: bool) bool {
    const mode = std.Io.Terminal.Mode.detect(
        io,
        std.Io.File.stdout(),
        no_color_env,
        false,
    ) catch return false;

    // This library writes ANSI sequences; `.windows_api` needs a separate
    // native-console renderer and therefore is not treated as ANSI support.
    return mode == .escape_codes;
}
