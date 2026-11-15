const color = @import("../color.zig");

pub const Style = struct {
    pub const dim = "\x1b[0;90m";
    pub const blue = "\x1b[1;94m";
    pub const green = "\x1b[0;1;92m";
    pub const bold = "\x1b[0;1m";
    pub const reset = "\x1b[0m";
};

pub const colorsEnabled = color.enabled;
