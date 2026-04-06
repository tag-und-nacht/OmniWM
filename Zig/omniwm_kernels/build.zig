const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "omniwm_kernels",
        .linkage = .static,
        .root_module = module,
    });
    lib.linkLibC();
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = module,
    });
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run OmniWM kernel Zig tests");
    test_step.dependOn(&run_tests.step);
}
