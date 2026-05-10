#!/bin/bash
set -e

echo "Building Zest for Linux..."
/home/jay/.local/share/zig/zig build -Doptimize=ReleaseSafe

echo "Packaging Linux release..."
rm -rf release/zest-0.1.0-linux
mkdir -p release/zest-0.1.0-linux
cp zig-out/bin/zest release/zest-0.1.0-linux/
cp -r assets release/zest-0.1.0-linux/
cp README.md release/zest-0.1.0-linux/
tar -czvf zest-0.1.0-linux.tar.gz -C release zest-0.1.0-linux

echo "Creating source zip..."
zip -r zest-v0.1.0-source.zip . -x "zig-out/*" ".zig-cache/*" "deps/*" "svg_venv/*" ".git/*" "release/*"

echo "Tagging release..."
git add .
git commit -m "release: v0.1.0 Linux"
git tag v0.1.0

echo "Done! Files ready: zest-0.1.0-linux.tar.gz, zest-v0.1.0-source.zip"
