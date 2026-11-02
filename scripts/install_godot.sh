#!/usr/bin/env bash
# Download the pinned Godot 4.7.2 Linux binary into .bin/ for headless checks.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="4.7.2-stable"
URL="https://github.com/godotengine/godot/releases/download/${VERSION}/Godot_v${VERSION}_linux.x86_64.zip"
mkdir -p .bin
curl -L "$URL" -o .bin/godot.zip
unzip -o .bin/godot.zip -d .bin
mv .bin/Godot_v${VERSION}_linux.x86_64 .bin/godot
chmod +x .bin/godot
rm .bin/godot.zip
echo "installed .bin/godot ($VERSION)"
