extends SceneTree
## E3-S48: one job of /balance reactions (ReactionField.run_jobs, scripts/reaction_field.gd),
## run in its own headless Godot so the jobs of a run play at once. It runs
## ReactionField.run_job on the job given as JSON and writes the result as JSON with full
## precision to the file given, so the parent's rows are the same as a run in one process.
## Exit code 0 when the result is written, 2 on bad arguments.
##
##   godot --headless --path . -s res://scripts/reaction_job.gd -- --job=<json> --out=<path>


func _initialize() -> void:
	var job: Variant = null
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--job="):
			job = JSON.parse_string(arg.substr(6))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	if typeof(job) != TYPE_DICTIONARY or out.is_empty():
		push_error("reaction_job: need --job=<json object> and --out=<path>")
		quit(2)
		return
	var result: Dictionary = ReactionField.new().run_job(job)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("reaction_job: cannot write %s" % out)
		quit(1)
		return
	f.store_string(JSON.stringify(result, "", false, true))
	f.close()
	quit(0)
