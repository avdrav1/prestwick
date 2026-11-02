# Decisions

Appended by `/decision`. Never edited in place.

## D1: Ball physics is custom, not Godot physics bodies (2026-11-01)
Options: RigidBody2D with faked height; RigidBody3D in a 3D world projected to 2D; custom 3D step over the height map.
Choice: custom step.
Why: deterministic by seed, cheap enough to run for off-screen guests, and the height map is the only collider that matters. Serves pillar 2 (readable shots).
Affects: golf/ball.gd, docs/design.md Ball

## D2: One main scene with Build and Play as states (2026-11-01)
Options: separate scenes with a loader; one scene with a state machine.
Choice: one scene.
Why: pillar 1 needs a one-click switch from placing a hole to standing on its tee. A scene load breaks that.
Affects: scenes/main.tscn, CLAUDE.md Architecture

## D3: Which Godot and GUT versions the project pins (2026-11-02)
Options: Godot 4.3 with GUT 9.4.0, as the repo first said (costs a ~50 MB download to `.bin/`, and 4.3 is four minors behind the installed editor); Godot 4.7.x with GUT 9.7.1 (no download, and GUT's own compatibility table pairs 9.7.1 with 4.7.x, but 4.7-only APIs can creep in).
Choice: Godot 4.7.x with GUT 9.7.1.
Why: the machine already runs 4.7.2 and CLAUDE.md asks only for 4.3+, so pinning 4.7 removes a mismatch between the editor and the checks instead of adding one. Serves pillar 4 (small, finishable scope): one engine, one toolchain.
Affects: project.godot (config/features), scripts/install_godot.sh, addons/gut, README.md, CLAUDE.md, .claude/skills/godot-check/SKILL.md
