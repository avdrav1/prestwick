extends SceneTree
## Run by scripts/screenshot.sh. Loads one scene in a real window, waits a few frames,
## saves what it drew to a PNG and quits. Never run headless: the dummy renderer
## draws no pixels.
##
## The scene renders into a SubViewport at the project's viewport size, so the PNG is the
## same size whatever the window manager does to the window (Hyprland tiles it).
##
## User args (after --): --scene=res://path.tscn --out=/abs/path.png [--frames=N] [--size=WxH]

var _frames_left: int = 10
var _viewport: SubViewport
var _out: String = ""
var _done: bool = false


func _initialize() -> void:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var scene_path: String = args.get("scene", "")
	_out = args.get("out", "")
	_frames_left = int(args.get("frames", "10"))
	if scene_path.is_empty() or _out.is_empty():
		push_error("screenshot: need --scene=res://... and --out=/path.png")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("screenshot: headless display draws nothing; run with a display")
		quit(2)
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("screenshot: cannot load %s" % scene_path)
		quit(2)
		return
	var size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	if args.has("size"):
		var wh: PackedStringArray = String(args["size"]).split("x")
		size = Vector2i(wh[0].to_int(), wh[1].to_int())
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_viewport)
	_viewport.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	if _done:
		return false
	_frames_left -= 1
	if _frames_left > 0:
		return false
	_done = true
	_capture.call_deferred()
	return false


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = _viewport.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("screenshot: viewport image is empty")
		quit(1)
		return
	var err: Error = img.save_png(_out)
	if err != OK:
		push_error("screenshot: save_png(%s) failed: %s" % [_out, error_string(err)])
		quit(1)
		return
	print("screenshot: %s %dx%d" % [_out, img.get_width(), img.get_height()])
	quit(0)
