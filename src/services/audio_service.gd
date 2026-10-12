class_name AudioService
extends Node
## Sound effects and music.
##
## Gameplay asks for sounds by id ("enemy_die"); the table in audio.json decides
## the file, level, pitch variance and - crucially for a swarm game - the minimum
## interval between repeats, so two hundred simultaneous kills cannot clip.
## Missing files are skipped silently, which keeps the game runnable while audio
## is still being produced.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

var played_count := 0

var _app: AppRoot
var _cfg: Dictionary
var _sfx: Dictionary
var _streams: Dictionary = {}
var _last_play_ms: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_id := ""
var _music_tween: Tween
var _muffle_effect := -1
var _silent := false


func setup(app: AppRoot) -> void:
	_app = app
	_cfg = app.data.audio
	_sfx = GameData.dict(_cfg, "sfx")
	_silent = app.headless
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	for i in GameData.integer(_cfg, "sfx_voices", 14):
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS_SFX
		add_child(voice)
		_voices.append(voice)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_MUSIC
		player.volume_db = -80.0
		add_child(player)
		_music.append(player)
	app.settings.changed.connect(_on_setting_changed)
	_apply_volumes()
	if not _silent:
		_preload()


## Loads every sound up front. On a phone, reading a file the first time a
## sound plays shows up as a dropped frame in the middle of the action.
func _preload() -> void:
	for id: String in _sfx:
		_stream(SFX_DIR, GameData.text(_sfx[id], "file"))
	var music := GameData.dict(_cfg, "music")
	for id: String in music:
		_stream(MUSIC_DIR, GameData.text(music[id], "file"))


func _build_buses() -> void:
	for bus_name: String in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
	# Safety net against clipping when the screen fills with explosions.
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	var music_bus := AudioServer.get_bus_index(BUS_MUSIC)
	if AudioServer.get_bus_effect_count(music_bus) == 0:
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = GameData.num(_cfg, "menu_lowpass_hz", 900.0)
		AudioServer.add_bus_effect(music_bus, lowpass)
		_muffle_effect = 0
		AudioServer.set_bus_effect_enabled(music_bus, _muffle_effect, false)
	else:
		_muffle_effect = 0


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key in [SettingsService.MASTER, SettingsService.MUSIC, SettingsService.SFX]:
		_apply_volumes()


func _apply_volumes() -> void:
	_set_bus_level(0, _app.settings.number(SettingsService.MASTER, 1.0))
	_set_bus_level(AudioServer.get_bus_index(BUS_MUSIC), _app.settings.number(SettingsService.MUSIC, 0.7))
	_set_bus_level(AudioServer.get_bus_index(BUS_SFX), _app.settings.number(SettingsService.SFX, 1.0))


func _set_bus_level(index: int, linear: float) -> void:
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


# ---------------------------------------------------------------------- sfx

## Plays a sound effect. `pitch` multiplies the table pitch (used for the
## rising chime as energy is collected in quick succession).
func play(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var def: Dictionary = _sfx.get(id, {})
	if def.is_empty():
		return
	var now := Time.get_ticks_msec()
	var interval_ms := int(GameData.num(def, "interval", 0.0) * 1000.0)
	if now - int(_last_play_ms.get(id, -100000)) < interval_ms:
		return
	_last_play_ms[id] = now
	played_count += 1
	if _silent:
		return
	var stream := _stream(SFX_DIR, GameData.text(def, "file"))
	if stream == null:
		return
	var voice := _free_voice()
	voice.stream = stream
	voice.volume_db = GameData.num(def, "vol", 0.0) + volume_db
	var variance := GameData.num(def, "pitch_var", 0.0)
	voice.pitch_scale = maxf(pitch * (1.0 + randf_range(-variance, variance)), 0.05)
	voice.play()


func _free_voice() -> AudioStreamPlayer:
	for i in _voices.size():
		var index := (_next_voice + i) % _voices.size()
		if not _voices[index].playing:
			_next_voice = (index + 1) % _voices.size()
			return _voices[index]
	# All busy: steal the oldest in rotation.
	var stolen := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return stolen


func _stream(dir: String, file: String) -> AudioStream:
	var path := dir + file + ".wav"
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_streams[path] = stream
	return stream


# -------------------------------------------------------------------- music

func play_music(id: String) -> void:
	if id == _music_id:
		return
	_music_id = id
	if _silent:
		return
	var def := GameData.dict(GameData.dict(_cfg, "music"), id)
	var stream := _stream(MUSIC_DIR, GameData.text(def, "file")) if not def.is_empty() else null
	var fade := GameData.num(_cfg, "music_fade", 0.8)
	var outgoing := _music[_music_active]
	_music_active = 1 - _music_active
	var incoming := _music[_music_active]
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	# Fade in linear gain, not dB, so the crossfade is audible for its whole length.
	_music_tween = create_tween().set_parallel(true)
	var from_db := outgoing.volume_db
	_music_tween.tween_method(func(gain: float) -> void: outgoing.volume_db = from_db + linear_to_db(maxf(gain, 0.0001)), 1.0, 0.0, fade)
	if stream != null:
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		var target_db := GameData.num(def, "vol", -8.0)
		incoming.stream = stream
		incoming.volume_db = -80.0
		incoming.play()
		_music_tween.tween_method(func(gain: float) -> void: incoming.volume_db = target_db + linear_to_db(maxf(gain, 0.0001)), 0.0, 1.0, fade)
	_music_tween.chain().tween_callback(outgoing.stop)


func stop_music() -> void:
	play_music("")


## Muffles the music (pause menu, level-up choice) so the moment reads as
## "time has stopped" without killing the track.
func set_muffled(on: bool) -> void:
	var bus := AudioServer.get_bus_index(BUS_MUSIC)
	if bus >= 0 and _muffle_effect >= 0:
		AudioServer.set_bus_effect_enabled(bus, _muffle_effect, on)


func set_music_pitch(scale: float) -> void:
	for player in _music:
		player.pitch_scale = scale


## Snapshot for diagnostics: is anything actually being mixed right now?
func debug_state() -> Dictionary:
	var voices := 0
	for voice in _voices:
		if voice.playing:
			voices += 1
	var current := _music[_music_active]
	return {
		"voices_playing": voices,
		"music_id": _music_id,
		"music_playing": current.playing,
		"music_position": current.get_playback_position() if current.playing else 0.0,
	}
