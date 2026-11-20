class_name HintSettings
extends RefCounted
## Which one-time hints the player has seen (E10-S3), kept in user://hint_settings.cfg like the
## audio settings (AudioSettings): a user setting, not part of a saved game, so a hint seen once
## stays seen across new games and launches. A file that is missing or unreadable reads as
## nothing seen.
##
## E21-S1 (D77): the opening flyover's `intro` flag lives here too: the intro plays on a launch
## that finds it unseen. Each flag only ever goes from unseen to seen, so save_to keeps a flag the
## file already has seen: a hints object loaded before another flag was written (the swing panel
## loads its own at start) never writes that flag back to unseen.

const PATH: String = "user://hint_settings.cfg"
const SECTION: String = "seen"
const SWING_KEY: String = "swing"
const INTRO_KEY: String = "intro"

## The swing bar's practice hint (SwingPanel) has been dismissed by a swing.
var swing_seen: bool = false
## E21-S1: the opening flyover has played (started) once.
var intro_seen: bool = false


## The settings saved at `path`; all unseen when there are none.
static func load_from(path: String = PATH) -> HintSettings:
	var s := HintSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	s.swing_seen = _seen(cfg, SWING_KEY)
	s.intro_seen = _seen(cfg, INTRO_KEY)
	return s


## Writes the flags to `path`, each seen if this object or the file already says so.
func save_to(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	var old := ConfigFile.new()
	var had := old.load(path) == OK
	cfg.set_value(SECTION, SWING_KEY, swing_seen or (had and _seen(old, SWING_KEY)))
	cfg.set_value(SECTION, INTRO_KEY, intro_seen or (had and _seen(old, INTRO_KEY)))
	return cfg.save(path)


## E21-S1: records at `path` that the intro has played, keeping every other flag.
static func mark_intro_seen(path: String = PATH) -> Error:
	var s := load_from(path)
	s.intro_seen = true
	return s.save_to(path)


static func _seen(cfg: ConfigFile, key: String) -> bool:
	var v: Variant = cfg.get_value(SECTION, key, false)
	return v is bool and v
