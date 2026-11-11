class_name HintSettings
extends RefCounted
## Which one-time hints the player has seen (E10-S3), kept in user://hint_settings.cfg like the
## audio settings (AudioSettings): a user setting, not part of a saved game, so a hint seen once
## stays seen across new games and launches. A file that is missing or unreadable reads as
## nothing seen.

const PATH: String = "user://hint_settings.cfg"
const SECTION: String = "seen"

## The swing bar's practice hint (SwingPanel) has been dismissed by a swing.
var swing_seen: bool = false


## The settings saved at `path`; all unseen when there are none.
static func load_from(path: String = PATH) -> HintSettings:
	var s := HintSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	var v: Variant = cfg.get_value(SECTION, "swing", false)
	s.swing_seen = v is bool and v
	return s


func save_to(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "swing", swing_seen)
	return cfg.save(path)
