const color = @import("../color.zig");

pub const ColorMode = color.ColorMode;

pub const HelpOptions = struct {
    width: usize = 80,
    color: ColorMode = .auto,
    no_color_env: bool = false,
    show_defaults: bool = true,
    show_env: bool = true,
    show_hidden: bool = false,
};
