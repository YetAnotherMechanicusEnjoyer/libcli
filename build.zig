const std = @import("std");

const Config = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
};

const ModuleImport = struct {
    name: []const u8,
    mod: *std.Build.Module,
};

const CMacro = struct {
    key: []const u8,
    value: []const u8,
};

fn createModule(b: *std.Build, root_path: []const u8, cfg: Config, link_libc: bool) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(root_path),
        .target = cfg.target,
        .optimize = cfg.optimize,
        .link_libc = link_libc,
    });

    if (cfg.optimize != .debug) {
        mod.strip = true;
        mod.error_tracing = false;
        mod.omit_frame_pointer = true;
    }

    return mod;
}

fn addModule(b: *std.Build, name: []const u8, root_path: []const u8, cfg: Config, link_libc: bool) *std.Build.Module {
    const mod = b.addModule(name, .{
        .root_source_file = b.path(root_path),
        .target = cfg.target,
        .optimize = cfg.optimize,
        .link_libc = link_libc,
    });

    if (cfg.optimize != .debug) {
        mod.strip = true;
        mod.error_tracing = false;
        mod.omit_frame_pointer = true;
    }

    return mod;
}

fn registerTest(
    b: *std.Build,
    test_step: *std.Build.Step,
    cfg: Config,
    name: []const u8,
    path: []const u8,
    imports: []const ModuleImport,
) void {
    const test_mod = createModule(b, path, cfg, false);
    for (imports) |imp|
        test_mod.addImport(imp.name, imp.mod);

    const test_artifact = b.addTest(.{
        .name = name,
        .root_module = test_mod,
    });
    test_step.dependOn(&b.addRunArtifact(test_artifact).step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Run tests");
    const docs_step = b.step("docs", "Generate documentation");

    // -------------------------
    // Config
    // -------------------------

    const cfg: Config = .{
        .target = target,
        .optimize = optimize,
    };

    // -------------------------
    // Components
    // -------------------------

    const cli_mod = addModule(b, "cli", "src/root.zig", cfg, true);

    const cli_lib = b.addLibrary(.{
        .name = "cli",
        .root_module = cli_mod,
    });
    b.installArtifact(cli_lib);

    // -------------------------
    // Tests
    // -------------------------

    const example_mod = createModule(b, "tests/example.zig", cfg, true);

    example_mod.addImport("cli", cli_mod);

    const example_exe = b.addExecutable(.{
        .name = "cli_test",
        .root_module = example_mod,
    });
    b.installArtifact(example_exe);

    // ---

    const tests = [_]struct {
        name: []const u8,
        path: []const u8,
        imports: []const ModuleImport,
    }{
        .{
            .name = "cli_test",
            .path = "tests/cli.zig",
            .imports = &[_]ModuleImport{
                .{ .name = "cli", .mod = cli_mod },
            },
        },
    };

    for (tests) |t|
        registerTest(b, test_step, cfg, t.name, t.path, t.imports);

    // -------------------------
    // Docs
    // -------------------------

    const doc_targets = [_]struct {
        name: []const u8,
        artifact: *std.Build.Step.Compile,
    }{
        .{ .name = "cli", .artifact = cli_lib },
    };

    for (doc_targets) |dt|
        docs_step.dependOn(&b.addInstallDirectory(.{
            .source_dir = dt.artifact.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = b.fmt("docs/{s}", .{dt.name}),
        }).step);
}
