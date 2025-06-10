const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("kioto/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "kioto",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const playground = b.addExecutable(.{
        .name = "playground",
        .root_source_file = b.path("kioto/playground.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_playground = b.addRunArtifact(playground);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const playground_step = b.step("playground", "Playground");
    playground_step.dependOn(&run_playground.step);
}
