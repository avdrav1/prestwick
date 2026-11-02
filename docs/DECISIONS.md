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
