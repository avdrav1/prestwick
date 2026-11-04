class_name HazardCuesShot
extends Node2D
## Screenshot fixture for E6-S16: the three end cues side by side on rough, at the sizes Play
## draws them at 1x (HazardCue): OB (ShotView's cue, slash over a ball), water, and the D20
## blocked marker (AimView's marker radius), so the colourblind rule can be checked: they
## differ by shape, not hue or slash direction. The lower row repeats them in grey.
## Run: scripts/screenshot.sh tests/fixtures/hazard_cues_shot.tscn

const RED: Color = Color8(216, 58, 58)
const INK: Color = Color8(26, 28, 34)
const CHALK: Color = Color8(240, 236, 224)
const ROUGH: Color = Color8(74, 110, 58)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), ROUGH)
	var shot := ShotView.new()
	var aim := AimView.new()
	var reach := ShotViewTuning.load_default().ob_slash_reach
	for row: int in 2:
		var y := 260.0 + row * 200.0
		var red := RED if row == 0 else Color(RED.get_luminance(), RED.get_luminance(), RED.get_luminance())
		var at := Vector2(400, y)
		HazardCue.draw_ob_ring(self, at, shot.hazard_cue_radius, 1.0, red, INK)
		draw_circle(at, shot.ball_radius + 1.0, INK)
		draw_circle(at, shot.ball_radius, CHALK)
		HazardCue.draw_ob_slash(self, at, shot.hazard_cue_radius, 1.0, reach, red, INK)
		HazardCue.draw_water(self, Vector2(640, y), shot.hazard_cue_radius, 1.0, CHALK, INK)
		HazardCue.draw_blocked(self, Vector2(880, y), aim.marker_radius, 1.0, red, INK, CHALK)
	shot.free()
	aim.free()
