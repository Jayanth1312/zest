const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Translate C headers into Zig modules
    const gl_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/c_gl.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const gl_mod = gl_translate.createModule();

    const ft_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/c_ft.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    ft_translate.addIncludePath(.{ .cwd_relative = "/usr/include/freetype2" });
    const ft_mod = ft_translate.createModule();

    const pty_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/c_pty.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const pty_mod = pty_translate.createModule();


    // Create the executable module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "c_gl", .module = gl_mod },
            .{ .name = "c_ft", .module = ft_mod },
            .{ .name = "c_pty", .module = pty_mod },
        },
    });

    const target_os = target.result.os.tag;

    if (target_os == .windows) {
        exe_mod.linkSystemLibrary("glfw3", .{});
        exe_mod.linkSystemLibrary("freetype", .{});
        exe_mod.linkSystemLibrary("opengl32", .{});
        exe_mod.linkSystemLibrary("gdi32", .{});
        exe_mod.linkSystemLibrary("shell32", .{});
    } else if (target_os == .macos) {
        exe_mod.linkSystemLibrary("glfw", .{});
        exe_mod.linkSystemLibrary("freetype", .{});
        exe_mod.linkFramework("OpenGL", .{});
        exe_mod.linkFramework("Cocoa", .{});
        exe_mod.linkFramework("IOKit", .{});
        exe_mod.linkFramework("CoreVideo", .{});
        exe_mod.linkFramework("QuartzCore", .{});
    } else {
        exe_mod.linkSystemLibrary("glfw3", .{});
        exe_mod.linkSystemLibrary("freetype2", .{});
        exe_mod.linkSystemLibrary("GL", .{});
        exe_mod.linkSystemLibrary("util", .{});
    }

    const exe = b.addExecutable(.{
        .name = "zest",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run Zest");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
