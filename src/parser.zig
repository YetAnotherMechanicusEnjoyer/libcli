const types = @import("parser/types.zig");
const engine = @import("parser/engine.zig");

pub const EnvironmentVariable = types.EnvironmentVariable;
pub const ParseOptions = types.Options;
pub const Parsed = types.Parsed;
pub const Outcome = types.Outcome;

/// Parse arguments excluding argv[0]. Allocation errors are returned as Zig
/// errors; ordinary command-line mistakes are represented by `.invalid`.
pub const parse = engine.parse;
