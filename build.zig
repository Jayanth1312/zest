const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Translate C headers into Zig modules (only for simple headers)
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

    // GTK4: use @cImport directly (translate-c can't handle GTK4's complex macros)
    // We pass include paths via the module so @cImport can find headers
    const gtk_include_paths = [_][]const u8{
        "/usr/include/gtk-4.0",
        "/usr/include/pango-1.0",
        "/usr/include/glib-2.0",
        "/usr/lib/x86_64-linux-gnu/glib-2.0/include",
        "/usr/include/harfbuzz",
        "/usr/include/freetype2",
        "/usr/include/libpng16",
        "/usr/include/libmount",
        "/usr/include/blkid",
        "/usr/include/fribidi",
        "/usr/include/cairo",
        "/usr/include/pixman-1",
        "/usr/include/gdk-pixbuf-2.0",
        "/usr/include/x86_64-linux-gnu",
        "/usr/include/webp",
        "/usr/include/graphene-1.0",
        "/usr/lib/x86_64-linux-gnu/graphene-1.0/include",
    };

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

    // Add GTK4 include paths to the exe module for @cImport
    for (gtk_include_paths) |path| {
        exe_mod.addIncludePath(.{ .cwd_relative = path });
    }

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
        // Linux: GTK4 + OpenGL + FreeType
        exe_mod.linkSystemLibrary("gtk-4", .{});
        exe_mod.linkSystemLibrary("gobject-2.0", .{});
        exe_mod.linkSystemLibrary("glib-2.0", .{});
        exe_mod.linkSystemLibrary("gio-2.0", .{});
        exe_mod.linkSystemLibrary("pango-1.0", .{});
        exe_mod.linkSystemLibrary("pangocairo-1.0", .{});
        exe_mod.linkSystemLibrary("cairo", .{});
        exe_mod.linkSystemLibrary("cairo-gobject", .{});
        exe_mod.linkSystemLibrary("gdk_pixbuf-2.0", .{});
        exe_mod.linkSystemLibrary("graphene-1.0", .{});
        exe_mod.linkSystemLibrary("harfbuzz", .{});
        exe_mod.linkSystemLibrary("freetype2", .{});
        exe_mod.linkSystemLibrary("epoxy", .{});
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
