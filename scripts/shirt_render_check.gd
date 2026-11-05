extends SceneTree
## E3-S28 review: renders the idle s_0 golfer once in every shirt through the real shader
## (art/sprites/golfer_shirt.gdshader, GolferArt.shirt_material), reads the pixels back and
## checks each is exactly the sheet's pixel with the key swapped as GolferArt.shirt_color says:
## skin, cap, ink and club unchanged, the shirt its palette colours. The GUT tests run headless,
## where nothing is drawn, so this is the check of the shader's output; run it by hand (it opens
## a window) after any change to the shader, the sheets or the shirt set (art/specs/golfer.md).
##
##   godot --path . -s res://scripts/shirt_render_check.gd
##
## Prints one line a shirt and exits 0 when every pixel matches, 1 otherwise.

const GAP: int = 25
## The most a channel may differ, 0 to 255 (the read-back rounds).
const TOLERANCE: int = 1


class _Figure:
	extends Node2D
	var tex: Texture2D

	func _draw() -> void:
		draw_texture(tex, Vector2.ZERO)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var art := GolferArt.load_default()
	var n := art.shirt_count()
	var vp := SubViewport.new()
	vp.size = Vector2i(n * GAP, 24)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var tex := art.frame(GolferArt.Anim.IDLE, 0, 0)
	for i in n:
		var f := _Figure.new()
		f.tex = tex
		f.position = Vector2(i * GAP, 0)
		f.material = art.shirt_material(i)
		vp.add_child(f)
	for k in 4:
		await RenderingServer.frame_post_draw
	var got := vp.get_texture().get_image()
	if got == null:
		push_error("no pixels read back: run it with a window, not --headless")
		quit(2)
		return
	var base := art.idle.texture.get_image().get_region(art.idle.region(art.idle.frame_index(&"s_0")))
	var bad := 0
	for i in n:
		var wrong := 0
		var first := ""
		for y in base.get_height():
			for x in base.get_width():
				var c := base.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var want := art.shirt_color(i, y) if c.is_equal_approx(art.shirt_key) else c
				var g := got.get_pixel(i * GAP + x, y)
				if absi(g.r8 - want.r8) > TOLERANCE or absi(g.g8 - want.g8) > TOLERANCE \
						or absi(g.b8 - want.b8) > TOLERANCE:
					wrong += 1
					if first.is_empty():
						first = " first (%d, %d): #%s, want #%s" % [x, y, g.to_html(false), want.to_html(false)]
		print("shirt %d (#%s): %s%s" % [i, art.shirt_body[i].to_html(false),
				"every pixel exact" if wrong == 0 else "%d pixels wrong" % wrong, first])
		bad += wrong
	quit(0 if bad == 0 else 1)
