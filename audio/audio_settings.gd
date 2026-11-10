class_name AudioSettings
extends RefCounted
## The player's volume per bus (E5-S4): Master, Music, Ambient and SFX (audio/bus_layout.tres),
## linear 0 to 1, kept in user://audio_settings.cfg so they come back next launch. A bus the
## file does not name, or a file that is missing or unreadable, takes AudioTuning's default.
## apply() sets them on the AudioServer; 0 mutes the bus.

const PATH: String = "user://audio_settings.cfg"
const SECTION: String = "volume"
const BUSES: Array[StringName] = [&"Master", &"Music", &"Ambient", &"SFX"]

## Bus name -> linear volume, 0 to 1.
var volumes: Dictionary = {}


func _init(tuning: AudioTuning = null) -> void:
	if tuning == null:
		tuning = AudioTuning.load_default()
	for bus in BUSES:
		volumes[bus] = tuning.default_volume(bus)


## The settings saved at `path`, over `tuning`'s defaults.
static func load_from(path: String = PATH, tuning: AudioTuning = null) -> AudioSettings:
	var s := AudioSettings.new(tuning)
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	for bus in BUSES:
		if not cfg.has_section_key(SECTION, String(bus)):
			continue
		var v: Variant = cfg.get_value(SECTION, String(bus))
		if v is float or v is int:
			s.volumes[bus] = clampf(float(v), 0.0, 1.0)
	return s


func save_to(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value(SECTION, String(bus), volume(bus))
	return cfg.save(path)


func volume(bus: StringName) -> float:
	return float(volumes.get(bus, 1.0))


func set_volume(bus: StringName, v: float) -> void:
	if BUSES.has(bus):
		volumes[bus] = clampf(v, 0.0, 1.0)


## Sets every bus's volume on the AudioServer. A bus the layout lacks is skipped.
func apply() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v := volume(bus)
		AudioServer.set_bus_mute(i, v <= 0.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
