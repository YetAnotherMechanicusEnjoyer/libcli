const command = @import("command.zig");
const color = @import("color.zig");
const diagnostic = @import("diagnostic.zig");
const value = @import("value.zig");
const parser = @import("parser.zig");
const render = @import("render.zig");

pub const Command = command.Command;
pub const Option = command.Option;
pub const Argument = command.Argument;
pub const Example = command.Example;
pub const Builtins = command.Builtins;
pub const RepeatPolicy = command.RepeatPolicy;
pub const ValueKind = command.ValueKind;

pub const ColorMode = color.ColorMode;
pub const colors_enabled = color.enabled;
pub const Value = value.Value;
pub const ValueSource = value.Source;

pub const Diagnostic = diagnostic.Diagnostic;
pub const DiagnosticKind = diagnostic.Kind;
pub const render_diagnostic = diagnostic.render;

pub const EnvironmentVariable = parser.EnvironmentVariable;
pub const ParseOptions = parser.ParseOptions;
pub const Parsed = parser.Parsed;
pub const ParseOutcome = parser.Outcome;
pub const HelpRequest = @import("parser/types.zig").HelpRequest;
pub const VersionRequest = @import("parser/types.zig").VersionRequest;
pub const parse = parser.parse;

pub const HelpOptions = render.HelpOptions;
pub const render_help = render.render_help;
pub const render_usage = render.render_usage;
pub const parse_color_mode = render.parse_color_mode;

test {
    _ = @import("parser.zig");
    _ = @import("parser/tests.zig");
    _ = @import("render/help.zig");
    _ = @import("render/usage.zig");
}
