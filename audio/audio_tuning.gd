class_name AudioTuning
extends Resource
## Designer-tuned numbers for the sound (E5-S4; audio/game_audio.gd, audio/audio_settings.gd).
## Loaded from res://audio/audio_tuning.tres.

const PATH: String = "res://audio/audio_tuning.tres"

## The volume of each bus (audio/bus_layout.tres) before the player sets one in the F2 sound
## panel, linear 0 to 1 (AudioSettings).
@export_range(0.0, 1.0) var default_master: float = 0.8
@export_range(0.0, 1.0) var default_music: float = 0.5
@export_range(0.0, 1.0) var default_ambient: float = 0.6
@export_range(0.0, 1.0) var default_sfx: float = 0.9
## The music loop's and the ambient bed's own player level, dB, under their bus volume.
@export var music_level_db: float = -6.0
@export var ambient_level_db: float = -4.0
## During a swing (first click until the ball rests) the music drops by this much, dB, so the
## shot's sounds read alone (pillar 2). It fades down over music_fade_out_s and back over
## music_fade_in_s.
@export var music_swing_db: float = -40.0
@export var music_fade_out_s: float = 0.25
@export var music_fade_in_s: float = 2.0
## Praise and complaint stings: at most one every this many seconds of game time, so a skip to
## morning or a group holing out together does not stack them.
@export var sting_min_gap_s: float = 1.5
## How many one-shot sounds may overlap (round-robin players on the SFX bus).
@export var sfx_voices: int = 6


## The default volume of `bus` (AudioSettings.BUSES), linear.
func default_volume(bus: StringName) -> float:
	match bus:
		&"Master":
			return default_master
		&"Music":
			return default_music
		&"Ambient":
			return default_ambient
		&"SFX":
			return default_sfx
	return 1.0


static func load_default() -> AudioTuning:
	return load(PATH) as AudioTuning
