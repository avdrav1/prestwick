# Export

How `/ship-it` builds Prestwick. Presets live in `export_presets.cfg` at the repo root; if one is missing, recreate it from the defaults below.

## Requirements

- Godot 4.7.2 (D3) on PATH as `godot`, or `.bin/godot`.
- Export templates for exactly that version in `~/.local/share/godot/export_templates/4.7.2.stable/`. Install them from the editor (Editor > Manage Export Templates) or unpack `Godot_v4.7.2-stable_export_templates.tpz` there. Unpacked they take about 2 GB; nothing in `scripts/` downloads them.
- Builds go to `build/`, which is git-ignored, so a fresh clone does not have it. Godot will not create it ("The given export path doesn't exist"), hence the `mkdir -p build` below.

## Presets

Both presets share these settings:

| Setting | Value | Why |
| --- | --- | --- |
| `export_filter` | `all_resources` | every scene, script and resource the game can load |
| `include_filter` | `courses/*.json` | course files are plain JSON, not resources, so they need naming |
| `exclude_filter` | `tests/*, addons/gut/*, scripts/*` | tests, the test framework and the dev tools stay out of the build |
| `binary_format/embed_pck` | `true` | one file per platform, nothing to lose beside it |
| `binary_format/architecture` | `x86_64` | |
| `texture_format/s3tc_bptc` | `true` | desktop GPUs |

| Preset name | Platform | Default path | Platform-specific |
| --- | --- | --- | --- |
| `Linux` | `Linux` | `build/prestwick-linux.x86_64` | none |
| `Windows` | `Windows Desktop` | `build/prestwick-win.exe` | `application/modify_resources=false` (no rcedit needed on Linux), codesign off |

## Commands

```
mkdir -p build
godot --headless --path . --export-release "Linux"   build/prestwick-<version>-linux.x86_64
godot --headless --path . --export-release "Windows" build/prestwick-<version>-win.exe
bash scripts/check_build.sh build/prestwick-<version>-linux.x86_64
```

`scripts/check_build.sh` launches the Linux build headless for 300 frames and fails on a non-zero exit, any `ERROR` or `WARNING` line (a course file left out of the pack warns), or the main scene not loading. The Windows build is not launched here; there is no Wine on the build machine.

## What the build cannot do

Official export templates refuse `--script`, so the scripted smoke (`scripts/playtest.sh`) cannot run inside a build. It runs against the project before export; `check_build.sh` then proves the exported pack boots the same main scene.
