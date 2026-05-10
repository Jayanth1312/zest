# <img src="assets/icon.png" width="40" valign="middle"> Zest

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
- **Hardware Accelerated**: Full OpenGL rendering pipeline.
- **Ultra-Low Latency**: Optimized for developers who demand instant feedback.
- **Sleek Aesthetic**: Minimalist design with a focus on typography.
- **Lightweight**: Tiny binary footprint (~1MB) and low memory usage.

## 🚀 Getting Started (v0.1.0 - Linux)

### Prerequisites

- **Zig**: 0.13.0 or later.
- **Dependencies**: GLFW3, FreeType2, and OpenGL headers.

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

## 📦 Releases

Current release: **v0.1.0 (Linux Only)**

- [zest-0.1.0-linux.tar.gz](zest-0.1.0-linux.tar.gz): Binary, icons, and assets.
- [Source Code](zest-v0.1.0-source.zip): Full Zig source for v0.1.0.

## 📜 License

MIT License.

---
Built with ⚡ by [Jayanth](https://github.com/Jayanth1312)

