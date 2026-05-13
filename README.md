# <img src="assets/icon.png" width="30" valign="middle"> Zest

**Zest** is a lightning-fast, GPU-accelerated terminal emulator built with **Zig**. Engineered for extreme performance, low latency, and a premium "Black Metal" developer aesthetic.

## 🏎 Why is Zest so fast?

Zest isn't just another terminal; it's built from the ground up for speed:

- **Zig Power**: Leveraging Zig's manual memory management and zero-overhead abstractions for a tight, efficient runtime.
- **Direct GPU Rendering**: Instead of relying on slow CPU-based text drawing, Zest uses an OpenGL-powered pipeline to render text directly on your graphics card.
- **Efficient Glyph Atlas**: Pre-renders and caches font characters into a GPU texture atlas, making text display nearly instantaneous.
- **Zero-Copy Pipeline**: Data flows from the PTY to the screen with minimal buffering and zero unnecessary copies.
- **Native PTY**: Uses raw Linux pseudo-terminals for the lowest possible latency between your shell and the display.

## ✨ Features

- **High-Fidelity Text**: Crisp font rasterization via FreeType.
- **Hardware Accelerated**: Full OpenGL ES rendering pipeline via libepoxy.
- **Ultra-Low Latency**: Optimized for developers who demand instant feedback.
- **Sleek Aesthetic**: Minimalist design with a focus on typography.
- **Lightweight**: Tiny binary footprint and low memory usage.
- **Native Wayland/X11 Support**: GTK4 backend with automatic fractional scaling (100%, 125%, 150%, 200%) — no blurry rendering.

## 🔄 What's New in v0.1.1

### GTK4 Migration
- Replaced GLFW with **GTK4** backend for native Wayland/X11 support
- **Sharp rendering at all DPI levels** — fractional scaling works perfectly on Wayland compositors
- GLArea-based OpenGL context with libepoxy for cross-platform GL function dispatch
- Raw `extern` declarations for GTK4 C interop (Zig 0.17.0-dev doesn't support `@cImport`)
- GLES 3.2 shaders (`#version 320 es`) for compatibility with GTK4's EGL context on Wayland

### Key Fixes
- Fixed `std.c.timespec` field access for Zig 0.17.0-dev (`sec`/`nsec` instead of `tv_sec`/`tv_nsec`)
- Fixed `@ptrCast` const qualifier discard with `@constCast` for GTK signal callbacks
- Fixed `g_signal_connect` macro → `g_signal_connect_data` function call
- Fixed `gtk_window_get_width/height` → `gtk_widget_get_width/height` (GTK4 API)
- Moved GL-dependent initialization (font, renderer, terminal, PTY) into `gl_realize_cb` (context must exist before shader compilation)

## 🚀 Getting Started (v0.1.1 - Linux)

### Prerequisites

- **Zig**: 0.17.0-dev.
- **Dependencies**: GTK4, FreeType2, Epoxy, Pango, and Cairo.

### Installation

1.  **Clone and Build**:
    ```bash
    git clone https://github.com/Jayanth1312/zest.git zest
    cd zest
    zig build -Doptimize=ReleaseSafe
    ```

2.  **Run**:
    ```bash
    ./zig-out/bin/zest
    ```

---
Built with ⚡ by [Jayanth](https://github.com/Jayanth1312)
