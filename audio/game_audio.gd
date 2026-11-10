class_name GameAudio
extends Node
## Every sound the game plays (E5-S4), on the buses of audio/bus_layout.tres: the ambient bed
## (Ambient) and the music loop (Music) from the start, the shot sounds and stings (SFX). The
## files are made by scripts/gen_audio.py (audio/LICENSE.md). A listener only: it reads the
## swing, the shot and the feed and never changes them.
##
## Readability first (pillar 2), a shot says its surface twice:
## - the strike, by the lie (SwingControl.lie_surface when `struck` fires): STRIKE, and `putt`
##   for any putt;
## - the first touchdown (ShotView.landed), by the surface there: LAND, water a splash, OB the
##   falling "no", trees a rustle.
## A flight the trees block (Ball.scattered) rustles when it is blocked; a ball that rolls into
## water or OB (Ball.penalty_strokes) splashes or buzzes when it stops there, unless its landing
## already said so; a holed ball plays `cup`.
## The music drops by AudioTuning.music_swing_db while a swing is in progress or its ball is
## moving, and comes back after. A guest's praise or complaint (ReactionFeed.added) plays its
## sting, at most one every sting_min_gap_s.
##
## `played` and `history` say which sound fired, so tests check the hooks without hearing them.

signal played(id: StringName)

const SOUND_DIR: String = "res://audio/"
const MUSIC: StringName = &"music"
const AMBIENT: StringName = &"ambient"
const PUTT: StringName = &"putt"
const SPLASH: StringName = &"splash"
const TREES: StringName = &"trees"
const OOB: StringName = &"oob"
const CUP: StringName = &"cup"
const PRAISE: StringName = &"praise"
const COMPLAINT: StringName = &"complaint"
## The strike by the lie. A ball never rests on water, OB or in trees (D15).
const STRIKE: Dictionary = {
	Surface.Type.TEE: &"strike_tee",
	Surface.Type.FAIRWAY: &"strike_fairway",
	Surface.Type.ROUGH: &"strike_rough",
	Surface.Type.BUNKER: &"strike_bunker",
	Surface.Type.CART_PATH: &"strike_cart_path",
	Surface.Type.GREEN: &"putt",
}
## The first touchdown by the surface.
const LAND: Dictionary = {
	Surface.Type.FAIRWAY: &"land_fairway",
	Surface.Type.TEE: &"land_fairway",
	Surface.Type.ROUGH: &"land_rough",
	Surface.Type.GREEN: &"land_green",
	Surface.Type.BUNKER: &"land_bunker",
	Surface.Type.CART_PATH: &"land_cart_path",
	Surface.Type.WATER: &"splash",
	Surface.Type.TREES: &"trees",
	Surface.Type.OOB: &"oob",
}

var tuning: AudioTuning
var settings: AudioSettings
## Where the settings are kept; tests point it at a file of their own.
var settings_path: String = AudioSettings.PATH
var music_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
## Every sound played, oldest first (the last `HISTORY_MAX`).
var history: Array[StringName] = []
## The music's drop now, dB: 0 at full, down to music_swing_db during a swing.
var music_offset_db: float = 0.0

const HISTORY_MAX: int = 64
## _exit_tree: the mix steps to wait for, and the longest wait, ms.
const EXIT_MIXES: int = 3
const EXIT_WAIT_MS: int = 250

var _swing_control: SwingControl
var _shot_view: ShotView
var _feed: ReactionFeed
var _streams: Dictionary = {}
var _next_voice: int = 0
## The ball whose shot the flags below are about.
var _ball: Ball
var _tree_said: bool = false
var _hazard_said: bool = false
var _cup_said: bool = false
## A putt starts on the ground (Ball.start_roll counts that as its landing): no touchdown sound.
var _putt: bool = false
## Seconds since the last sting.
var _since_sting: float = INF


func _ready() -> void:
	if tuning == null:
		tuning = AudioTuning.load_default()
	settings = AudioSettings.load_from(settings_path, tuning)
	settings.apply()
	music_player = _player(&"Music", "Music")
	ambient_player = _player(&"Ambient", "Ambient")
	for i in maxi(1, tuning.sfx_voices):
		sfx_players.append(_player(&"SFX", "Sfx%d" % i))
	music_player.volume_db = tuning.music_level_db
	ambient_player.volume_db = tuning.ambient_level_db
	music_player.stream = sound(MUSIC)
	ambient_player.stream = sound(AMBIENT)
	music_player.play()
	ambient_player.play()
	var root := get_tree().root
	if not root.tree_exiting.is_connected(_drain_mixer):
		root.tree_exiting.connect(_drain_mixer)


## Stops every player as the scene goes.
func _exit_tree() -> void:
	for p: AudioStreamPlayer in [music_player, ambient_player] + sfx_players:
		if p != null:
			p.stop()
			p.stream = null


## At quit, after every node has stopped its players (_exit_tree; the root's tree_exiting comes
## last), lets the audio server's mixer run a few steps so it drops their playbacks: the server
## frees a stopped playback only in a later mix, and a quit tearing the tree down at once would
## leave the beds' playbacks and their WAVs "still in use at exit". Waits at most EXIT_WAIT_MS.
static func _drain_mixer() -> void:
	var mixes := 0
	var waited := 0
	var last := AudioServer.get_time_since_last_mix()
	while mixes < EXIT_MIXES and waited < EXIT_WAIT_MS:
		OS.delay_msec(1)
		waited += 1
		var t := AudioServer.get_time_since_last_mix()
		if t < last:
			mixes += 1
		last = t


## Listens to the swing, the shot and the guests' feed from now on.
func bind(swing_control: SwingControl, shot_view: ShotView, feed: ReactionFeed) -> void:
	_swing_control = swing_control
	_shot_view = shot_view
	_feed = feed
	swing_control.struck.connect(_on_struck)
	shot_view.landed.connect(_on_landed)
	if feed != null:
		feed.added.connect(_on_feed_added)


## The volume of `bus` (AudioSettings.BUSES), linear 0 to 1.
func volume(bus: StringName) -> float:
	return settings.volume(bus)


## Sets, applies and saves the volume of `bus`.
func set_volume(bus: StringName, v: float) -> void:
	settings.set_volume(bus, v)
	settings.apply()
	settings.save_to(settings_path)


## True while the music is held down: a swing in progress or its ball moving.
func music_ducked() -> bool:
	return _swing_control != null and _swing_control.active \
			and (_swing_control.swing.in_progress() or _swing_control.is_ball_moving())


## The stream for sound `id` (audio/<id>.wav), cached; null when the file is missing.
func sound(id: StringName) -> AudioStream:
	if not _streams.has(id):
		var path := SOUND_DIR + String(id) + ".wav"
		_streams[id] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[id]


## Plays one-shot `id` on the SFX bus and records it.
func play(id: StringName) -> void:
	history.append(id)
	if history.size() > HISTORY_MAX:
		history.remove_at(0)
	var s := sound(id)
	if s != null and not sfx_players.is_empty():
		var p := sfx_players[_next_voice]
		_next_voice = (_next_voice + 1) % sfx_players.size()
		p.stream = s
		p.play()
	played.emit(id)


func _process(delta: float) -> void:
	advance(delta)


## One frame: the shot's polled sounds, the music's drop and the sting clock.
func advance(delta: float) -> void:
	_since_sting += delta
	_poll_ball()
	var target := tuning.music_swing_db if music_ducked() else 0.0
	var span := tuning.music_fade_out_s if target < music_offset_db else tuning.music_fade_in_s
	var rate := absf(tuning.music_swing_db) / maxf(span, 0.001)
	music_offset_db = move_toward(music_offset_db, target, rate * delta)
	if music_player != null:
		music_player.volume_db = tuning.music_level_db + music_offset_db


func _on_struck(shot: ShotLaunch) -> void:
	_sync_ball()
	_putt = shot.is_putt()
	if _putt:
		play(PUTT)
	else:
		play(STRIKE.get(_swing_control.lie_surface(), &"strike_fairway"))


func _on_landed(at: Vector3) -> void:
	_sync_ball()
	if _ball == null or _putt:
		return
	# Trees that scatter a flight can drop it to the ground in the same tick: rustle first.
	if _ball.scattered and not _tree_said:
		_tree_said = true
		play(TREES)
	var id: StringName = LAND.get(_ball.field.surface_at(at.x, at.y), &"land_fairway")
	if id == SPLASH or id == OOB:
		_hazard_said = true
	elif id == TREES:
		if _tree_said:
			return
		_tree_said = true
	play(id)


func _on_feed_added(entry: ReactionFeed.Entry) -> void:
	if entry.kind == GuestReaction.Kind.NEUTRAL or _since_sting < tuning.sting_min_gap_s:
		return
	_since_sting = 0.0
	play(PRAISE if entry.is_praise() else COMPLAINT)


## A new ball in the shot view starts a new shot's flags.
func _sync_ball() -> void:
	var b: Ball = _shot_view.ball if _shot_view != null else null
	if b != _ball:
		_ball = b
		_tree_said = false
		_hazard_said = false
		_cup_said = false
		_putt = false


func _poll_ball() -> void:
	if _shot_view == null:
		return
	_sync_ball()
	if _ball == null:
		return
	if _ball.scattered and not _tree_said:
		_tree_said = true
		play(TREES)
	if _ball.penalty_strokes > 0 and not _hazard_said:
		_hazard_said = true
		play(SPLASH if _ball.hazard == Ball.Hazard.WATER else OOB)
	if _ball.holed and not _cup_said:
		_cup_said = true
		play(CUP)


func _player(bus: StringName, node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus
	add_child(p)
	return p
