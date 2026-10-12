extends SceneTree
## Procedural audio generator. Synthesises every sound effect and both music
## loops from oscillators, noise and envelopes and writes them as 16-bit WAVs,
## so the game ships with a complete, licence-free soundscape from day one.
## These are placeholders in the classic arcade idiom - replace any file in
## assets/audio/ with a produced sound of the same name and nothing else changes.
##
## Usage:
##   godot --headless --path . --script res://tools/generate_audio.gd
##   godot --headless --path . --script res://tools/generate_audio.gd -- --only=level_up,nova
##   godot --headless --path . --script res://tools/generate_audio.gd -- --skip-music
##
## Output is deterministic: each sound seeds its own noise generator.

const RATE := 44100
const MUSIC_RATE := 32000
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"

const SINE := 0
const PULSE := 1
const SAW := 2
const TRI := 3

var _buf := PackedFloat32Array()
var _rate := RATE
var _wrap := false
var _rng := RandomNumberGenerator.new()
var _only := PackedStringArray()
var _report: Array[String] = []


func _init() -> void:
	var skip_music := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
		elif arg == "--skip-music":
			skip_music = true
	for dir: String in [SFX_DIR, MUSIC_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var started := Time.get_ticks_msec()
	_make_sfx()
	if not skip_music:
		_make_music()
	for line in _report:
		print(line)
	print("Generated %d files in %.1f s" % [_report.size(), (Time.get_ticks_msec() - started) / 1000.0])
	quit()


# ------------------------------------------------------------------- toolkit

func _wanted(sound: String) -> bool:
	return _only.is_empty() or _only.has(sound)


func _begin(sound: String, seconds: float, rate: int = RATE, wrap: bool = false) -> void:
	_rate = rate
	_wrap = wrap
	_buf = PackedFloat32Array()
	_buf.resize(int(seconds * float(rate)))
	_rng.seed = hash(sound)


## Adds one oscillator note. Pitch glides exponentially from f0 to f1; volume
## ramps up over `attack` then falls as (1 - t)^curve. `lp` > 0 is a one-pole
## low-pass in Hz.
func _tone(at: float, dur: float, wave: int, f0: float, f1: float, vol: float, attack: float = 0.004,
		curve: float = 2.0, duty: float = 0.5, lp: float = 0.0, vib_hz: float = 0.0, vib_depth: float = 0.0) -> void:
	var rate := float(_rate)
	var start := int(at * rate)
	var size := _buf.size()
	# Loops let a note run past the end and carry on from the start.
	var n := int(dur * rate) if _wrap else mini(int(dur * rate), size - start)
	if n <= 0:
		return
	var buf := _buf
	var phase := 0.0
	var ratio := f1 / maxf(f0, 0.01)
	var attack_n := maxf(attack * rate, 1.0)
	var a := 1.0 - exp(-TAU * lp / rate) if lp > 0.0 else 1.0
	var low := 0.0
	var inv_n := 1.0 / float(n)
	for i in n:
		var t := float(i) * inv_n
		var freq := f0 * pow(ratio, t)
		if vib_hz > 0.0:
			freq *= 1.0 + vib_depth * sin(TAU * vib_hz * float(i) / rate)
		phase += freq / rate
		if phase >= 1.0:
			phase -= 1.0
		var s: float
		if wave == SINE:
			s = sin(TAU * phase)
		elif wave == PULSE:
			s = 1.0 if phase < duty else -1.0
		elif wave == SAW:
			s = phase * 2.0 - 1.0
		else:
			s = 4.0 * absf(phase - 0.5) - 1.0
		var env := minf(float(i) / attack_n, 1.0) * pow(1.0 - t, curve)
		low += a * (s - low)
		buf[(start + i) % size] += low * env * vol


## Adds filtered white noise. The low-pass cutoff glides from lp0 to lp1; `hp`
## removes everything below it (for hiss, crackle and "air").
func _noise(at: float, dur: float, vol: float, lp0: float, lp1: float, hp: float = 0.0, attack: float = 0.002, curve: float = 2.0) -> void:
	var rate := float(_rate)
	var start := int(at * rate)
	var size := _buf.size()
	var n := int(dur * rate) if _wrap else mini(int(dur * rate), size - start)
	if n <= 0:
		return
	var buf := _buf
	var rng := _rng
	var low := 0.0
	var floor_low := 0.0
	var ratio := lp1 / maxf(lp0, 1.0)
	var attack_n := maxf(attack * rate, 1.0)
	var hp_a := 1.0 - exp(-TAU * hp / rate) if hp > 0.0 else 0.0
	var inv_n := 1.0 / float(n)
	for i in n:
		var t := float(i) * inv_n
		var cutoff := lp0 * pow(ratio, t)
		var a := 1.0 - exp(-TAU * cutoff / rate)
		var white := rng.randf() * 2.0 - 1.0
		low += a * (white - low)
		var s := low
		if hp > 0.0:
			floor_low += hp_a * (low - floor_low)
			s = low - floor_low
		var env := minf(float(i) / attack_n, 1.0) * pow(1.0 - t, curve)
		buf[(start + i) % size] += s * env * vol


## Feedback echo over the whole buffer. For loops it runs twice around so the
## echoes of the last bar are already ringing when the loop restarts.
func _echo(delay: float, feedback: float, mix: float) -> void:
	var d := int(delay * float(_rate))
	var buf := _buf
	var size := buf.size()
	var wet := buf.duplicate()
	if _wrap:
		for lap in 2:
			for i in size:
				wet[i] = buf[i] + wet[(i - d + size) % size] * feedback
	else:
		for i in range(d, size):
			wet[i] += wet[i - d] * feedback
	for i in size:
		buf[i] += (wet[i] - buf[i]) * mix


## Normalises to `peak` (linear), adds click-free edges, writes a mono WAV.
func _save(dir: String, sound: String, peak: float = 0.7, loop: bool = false) -> void:
	var buf := _buf
	var n := buf.size()
	var top := 0.0001
	var sum := 0.0
	for i in n:
		var v := absf(buf[i])
		if v > top:
			top = v
		sum += buf[i] * buf[i]
	var gain := peak / top
	var fade := mini(int(0.004 * float(_rate)), n / 2)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := buf[i] * gain
		if not loop:
			if i < fade:
				s *= float(i) / float(fade)
			elif i >= n - fade:
				s *= float(n - 1 - i) / float(fade)
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _rate
	wav.stereo = false
	wav.data = bytes
	var path := dir + sound + ".wav"
	var err := wav.save_to_wav(path)
	var rms := sqrt(sum / float(maxi(n, 1))) * gain
	_report.append("  %-16s %5.2f s  peak %.2f  rms %.3f%s" % [sound, float(n) / float(_rate), peak, rms, "" if err == OK else "  SAVE FAILED"])


func _note(semitones_from_a4: float) -> float:
	return 440.0 * pow(2.0, semitones_from_a4 / 12.0)


## Quick run of notes: semitone offsets from A4, each `step` seconds apart.
func _arp(at: float, notes: Array, step: float, length: float, wave: int, vol: float, duty: float = 0.5, lp: float = 0.0) -> void:
	for i in notes.size():
		var f := _note(float(notes[i]))
		_tone(at + step * float(i), length, wave, f, f, vol, 0.003, 2.2, duty, lp)


# ----------------------------------------------------------------------- sfx

func _make_sfx() -> void:
	# ---- interface
	if _wanted("ui_click"):
		_begin("ui_click", 0.06)
		_tone(0.0, 0.05, SINE, 1500.0, 900.0, 0.8, 0.001, 2.5)
		_noise(0.0, 0.012, 0.25, 6000.0, 3000.0, 1500.0)
		_save(SFX_DIR, "ui_click", 0.6)
	if _wanted("ui_back"):
		_begin("ui_back", 0.09)
		_tone(0.0, 0.08, SINE, 760.0, 400.0, 0.8, 0.001, 2.2)
		_save(SFX_DIR, "ui_back", 0.6)
	if _wanted("ui_tab"):
		_begin("ui_tab", 0.07)
		_tone(0.0, 0.06, TRI, 900.0, 1250.0, 0.8, 0.001, 2.4)
		_save(SFX_DIR, "ui_tab", 0.55)
	if _wanted("ui_open"):
		_begin("ui_open", 0.14)
		_tone(0.0, 0.12, SINE, 480.0, 960.0, 0.7, 0.01, 1.8)
		_noise(0.0, 0.1, 0.12, 800.0, 5000.0, 600.0, 0.03)
		_save(SFX_DIR, "ui_open", 0.55)
	if _wanted("ui_error"):
		_begin("ui_error", 0.26)
		_tone(0.0, 0.1, PULSE, 190.0, 180.0, 0.7, 0.002, 1.2, 0.5, 1800.0)
		_tone(0.12, 0.13, PULSE, 150.0, 140.0, 0.7, 0.002, 1.2, 0.5, 1800.0)
		_save(SFX_DIR, "ui_error", 0.6)
	if _wanted("ui_purchase"):
		_begin("ui_purchase", 0.5)
		_arp(0.0, [3, 7, 10, 15], 0.06, 0.26, TRI, 0.6)
		_arp(0.0, [15, 19, 22, 27], 0.06, 0.2, SINE, 0.25)
		_noise(0.16, 0.3, 0.1, 9000.0, 4000.0, 3000.0, 0.01, 2.5)
		_save(SFX_DIR, "ui_purchase", 0.7)
	if _wanted("ui_claim"):
		_begin("ui_claim", 0.4)
		_arp(0.0, [7, 12, 19], 0.07, 0.24, TRI, 0.6)
		_tone(0.14, 0.24, SINE, _note(31.0), _note(31.0), 0.2, 0.002, 2.5)
		_save(SFX_DIR, "ui_claim", 0.7)
	if _wanted("count_tick"):
		_begin("count_tick", 0.03)
		_tone(0.0, 0.025, SINE, 1900.0, 1700.0, 0.8, 0.001, 2.0)
		_save(SFX_DIR, "count_tick", 0.45)
	if _wanted("reward"):
		_begin("reward", 0.6)
		_arp(0.0, [3, 7, 10, 15, 19], 0.055, 0.34, TRI, 0.55)
		_arp(0.02, [15, 19, 22, 27, 31], 0.055, 0.25, SINE, 0.22)
		_save(SFX_DIR, "reward", 0.7)

	# ---- level-up flow
	if _wanted("card_show"):
		_begin("card_show", 0.16)
		_noise(0.0, 0.14, 0.5, 700.0, 6000.0, 400.0, 0.04, 1.5)
		_tone(0.03, 0.1, SINE, 620.0, 980.0, 0.35, 0.01, 2.0)
		_save(SFX_DIR, "card_show", 0.5)
	if _wanted("upgrade_pick"):
		_begin("upgrade_pick", 0.42)
		_tone(0.0, 0.16, SINE, 130.0, 55.0, 0.9, 0.002, 1.6)
		_tone(0.0, 0.3, TRI, _note(10.0), _note(10.0), 0.5, 0.002, 2.2)
		_tone(0.06, 0.32, TRI, _note(17.0), _note(17.0), 0.5, 0.002, 2.2)
		_noise(0.0, 0.05, 0.3, 8000.0, 2000.0, 1500.0)
		_save(SFX_DIR, "upgrade_pick", 0.75)
	if _wanted("level_up"):
		_begin("level_up", 0.8)
		_arp(0.0, [3, 7, 10, 15, 19, 22], 0.06, 0.36, PULSE, 0.4, 0.3, 5000.0)
		_arp(0.0, [15, 19, 22, 27, 31, 34], 0.06, 0.3, SINE, 0.25)
		_tone(0.0, 0.3, SINE, 220.0, 440.0, 0.3, 0.02, 1.5)
		_noise(0.3, 0.45, 0.1, 10000.0, 5000.0, 4000.0, 0.02, 2.5)
		_save(SFX_DIR, "level_up", 0.75)
	if _wanted("reroll"):
		_begin("reroll", 0.24)
		_tone(0.0, 0.1, TRI, 950.0, 520.0, 0.7, 0.002, 1.6)
		_tone(0.1, 0.12, TRI, 520.0, 1100.0, 0.7, 0.002, 1.8)
		_save(SFX_DIR, "reroll", 0.6)
	if _wanted("synergy"):
		_begin("synergy", 1.5)
		for semis: int in [-9, -2, 3, 7, 10]:
			_tone(0.0, 1.4, SAW, _note(float(semis)), _note(float(semis)) * 1.004, 0.22, 0.25, 1.4, 0.5, 2600.0)
		_arp(0.3, [15, 19, 22, 27, 31], 0.07, 0.6, SINE, 0.3)
		_noise(0.0, 1.2, 0.12, 500.0, 9000.0, 300.0, 0.5, 1.5)
		_save(SFX_DIR, "synergy", 0.8)
	if _wanted("cache_open"):
		_begin("cache_open", 0.75)
		_tone(0.0, 0.32, SINE, 280.0, 1250.0, 0.5, 0.02, 1.2)
		_noise(0.0, 0.3, 0.15, 600.0, 7000.0, 400.0, 0.1)
		_arp(0.28, [10, 15, 22], 0.07, 0.36, TRI, 0.5)
		_save(SFX_DIR, "cache_open", 0.75)

	# ---- weapons
	if _wanted("shoot_pulse"):
		_begin("shoot_pulse", 0.11)
		_tone(0.0, 0.1, PULSE, 1150.0, 300.0, 0.7, 0.001, 2.0, 0.25, 6000.0)
		_noise(0.0, 0.02, 0.2, 7000.0, 3000.0, 2000.0)
		_save(SFX_DIR, "shoot_pulse", 0.55)
	if _wanted("shoot_scatter"):
		_begin("shoot_scatter", 0.2)
		_noise(0.0, 0.17, 0.9, 3800.0, 600.0, 0.0, 0.001, 2.2)
		_tone(0.0, 0.12, PULSE, 380.0, 110.0, 0.5, 0.001, 1.8, 0.4, 2500.0)
		_save(SFX_DIR, "shoot_scatter", 0.7)
	if _wanted("shoot_drone"):
		_begin("shoot_drone", 0.07)
		_tone(0.0, 0.06, PULSE, 1700.0, 950.0, 0.7, 0.001, 2.2, 0.2, 7000.0)
		_save(SFX_DIR, "shoot_drone", 0.5)
	if _wanted("shoot_missile"):
		_begin("shoot_missile", 0.36)
		_noise(0.0, 0.34, 0.7, 500.0, 4500.0, 250.0, 0.04, 1.6)
		_tone(0.0, 0.3, SAW, 180.0, 520.0, 0.3, 0.02, 1.6, 0.5, 2200.0)
		_save(SFX_DIR, "shoot_missile", 0.65)
	if _wanted("lightning"):
		_begin("lightning", 0.2)
		_noise(0.0, 0.18, 0.9, 9000.0, 2500.0, 1800.0, 0.001, 1.6)
		_tone(0.0, 0.12, SAW, 1900.0, 180.0, 0.4, 0.001, 2.0, 0.5, 5000.0, 95.0, 0.4)
		_tone(0.0, 0.05, PULSE, 90.0, 60.0, 0.4, 0.001, 1.5)
		_save(SFX_DIR, "lightning", 0.65)
	if _wanted("nova"):
		_begin("nova", 0.5)
		_tone(0.0, 0.45, SINE, 950.0, 140.0, 0.6, 0.004, 1.6)
		_tone(0.0, 0.3, TRI, 2500.0, 1200.0, 0.25, 0.002, 2.4)
		_noise(0.0, 0.45, 0.4, 9000.0, 1500.0, 2500.0, 0.01, 1.8)
		_save(SFX_DIR, "nova", 0.7)
	if _wanted("laser"):
		_begin("laser", 0.6)
		_tone(0.0, 0.58, SAW, 520.0, 500.0, 0.4, 0.02, 0.9, 0.5, 3200.0, 32.0, 0.03)
		_tone(0.0, 0.58, SINE, 1040.0, 1000.0, 0.3, 0.02, 0.9)
		_noise(0.0, 0.5, 0.15, 6000.0, 6000.0, 3000.0, 0.02, 1.0)
		_save(SFX_DIR, "laser", 0.6)
	if _wanted("mine_drop"):
		_begin("mine_drop", 0.09)
		_tone(0.0, 0.07, TRI, 520.0, 300.0, 0.8, 0.001, 2.0)
		_noise(0.0, 0.015, 0.25, 5000.0, 2000.0, 1000.0)
		_save(SFX_DIR, "mine_drop", 0.5)
	if _wanted("blade_hit"):
		_begin("blade_hit", 0.07)
		_noise(0.0, 0.05, 0.7, 10000.0, 5000.0, 3500.0, 0.001, 2.2)
		_tone(0.0, 0.05, TRI, 2300.0, 1500.0, 0.4, 0.001, 2.4)
		_save(SFX_DIR, "blade_hit", 0.5)
	if _wanted("singularity"):
		_begin("singularity", 0.8)
		_tone(0.0, 0.78, SINE, 230.0, 52.0, 0.8, 0.08, 1.0)
		_tone(0.0, 0.78, SAW, 115.0, 26.0, 0.25, 0.1, 1.0, 0.5, 700.0)
		_noise(0.0, 0.7, 0.3, 2500.0, 250.0, 0.0, 0.2, 1.2)
		_save(SFX_DIR, "singularity", 0.75)
	if _wanted("implosion"):
		_begin("implosion", 0.7)
		_tone(0.0, 0.2, SINE, 60.0, 260.0, 0.6, 0.12, 0.4)
		_noise(0.18, 0.5, 1.0, 3200.0, 180.0, 0.0, 0.001, 2.0)
		_tone(0.18, 0.45, SINE, 110.0, 38.0, 0.9, 0.001, 1.6)
		_save(SFX_DIR, "implosion", 0.8)

	# ---- explosions and impacts
	if _wanted("explosion_s"):
		_begin("explosion_s", 0.26)
		_noise(0.0, 0.24, 1.0, 2800.0, 280.0, 0.0, 0.001, 2.2)
		_tone(0.0, 0.18, SINE, 170.0, 58.0, 0.7, 0.001, 1.8)
		_save(SFX_DIR, "explosion_s", 0.7)
	if _wanted("explosion_m"):
		_begin("explosion_m", 0.45)
		_noise(0.0, 0.42, 1.0, 2200.0, 180.0, 0.0, 0.001, 2.0)
		_tone(0.0, 0.32, SINE, 130.0, 44.0, 0.9, 0.001, 1.6)
		_save(SFX_DIR, "explosion_m", 0.78)
	if _wanted("explosion_l"):
		_begin("explosion_l", 0.9)
		_noise(0.0, 0.85, 1.0, 1700.0, 110.0, 0.0, 0.001, 1.8)
		_noise(0.02, 0.3, 0.4, 9000.0, 2000.0, 2500.0, 0.001, 2.5)
		_tone(0.0, 0.65, SINE, 95.0, 32.0, 1.0, 0.001, 1.4)
		_save(SFX_DIR, "explosion_l", 0.85)
	if _wanted("shatter"):
		_begin("shatter", 0.22)
		_noise(0.0, 0.14, 0.7, 12000.0, 6000.0, 4500.0, 0.001, 2.0)
		for k in 5:
			var f := _rng.randf_range(2800.0, 5200.0)
			_tone(0.01 + 0.025 * float(k), 0.1, SINE, f, f * 0.96, 0.25, 0.001, 2.6)
		_save(SFX_DIR, "shatter", 0.6)
	if _wanted("enemy_hit"):
		_begin("enemy_hit", 0.045)
		_noise(0.0, 0.035, 0.7, 5000.0, 1500.0, 800.0, 0.001, 2.0)
		_tone(0.0, 0.035, PULSE, 320.0, 200.0, 0.4, 0.001, 2.0, 0.5, 2500.0)
		_save(SFX_DIR, "enemy_hit", 0.45)
	if _wanted("enemy_die"):
		_begin("enemy_die", 0.13)
		_tone(0.0, 0.11, PULSE, 540.0, 120.0, 0.6, 0.001, 1.8, 0.35, 3500.0)
		_noise(0.0, 0.08, 0.5, 4000.0, 700.0, 0.0, 0.001, 2.2)
		_save(SFX_DIR, "enemy_die", 0.55)
	if _wanted("elite_die"):
		_begin("elite_die", 0.7)
		_noise(0.0, 0.6, 1.0, 2400.0, 160.0, 0.0, 0.001, 1.8)
		_tone(0.0, 0.5, PULSE, 620.0, 70.0, 0.4, 0.001, 1.5, 0.3, 3000.0)
		_tone(0.0, 0.5, SINE, 120.0, 40.0, 0.9, 0.001, 1.5)
		_arp(0.08, [19, 15, 10], 0.07, 0.3, TRI, 0.25)
		_save(SFX_DIR, "elite_die", 0.82)
	if _wanted("enemy_shoot"):
		_begin("enemy_shoot", 0.11)
		_tone(0.0, 0.1, PULSE, 480.0, 760.0, 0.7, 0.002, 1.8, 0.5, 3000.0)
		_save(SFX_DIR, "enemy_shoot", 0.5)
	if _wanted("dash_warn"):
		_begin("dash_warn", 0.17)
		_tone(0.0, 0.06, SAW, 880.0, 880.0, 0.7, 0.002, 0.8, 0.5, 3500.0)
		_tone(0.09, 0.07, SAW, 1040.0, 1040.0, 0.7, 0.002, 0.9, 0.5, 3500.0)
		_save(SFX_DIR, "dash_warn", 0.5)

	# ---- pickups
	if _wanted("pickup_xp"):
		_begin("pickup_xp", 0.06)
		_tone(0.0, 0.055, SINE, 1250.0, 1750.0, 0.8, 0.002, 2.0)
		_save(SFX_DIR, "pickup_xp", 0.45)
	if _wanted("pickup_credit"):
		_begin("pickup_credit", 0.16)
		_tone(0.0, 0.07, SINE, _note(22.0), _note(22.0), 0.7, 0.001, 2.2)
		_tone(0.05, 0.1, SINE, _note(27.0), _note(27.0), 0.7, 0.001, 2.4)
		_save(SFX_DIR, "pickup_credit", 0.55)
	if _wanted("pickup_special"):
		_begin("pickup_special", 0.5)
		_arp(0.0, [7, 14, 19, 26], 0.06, 0.3, TRI, 0.55)
		_noise(0.1, 0.35, 0.12, 10000.0, 5000.0, 4000.0, 0.02, 2.2)
		_save(SFX_DIR, "pickup_special", 0.7)

	# ---- player
	if _wanted("player_hurt"):
		_begin("player_hurt", 0.3)
		_tone(0.0, 0.26, SAW, 320.0, 85.0, 0.8, 0.001, 1.5, 0.5, 2200.0)
		_noise(0.0, 0.12, 0.6, 3000.0, 600.0, 0.0, 0.001, 2.0)
		_tone(0.0, 0.1, SINE, 110.0, 50.0, 0.7, 0.001, 1.5)
		_save(SFX_DIR, "player_hurt", 0.8)
	if _wanted("player_death"):
		_begin("player_death", 1.3)
		_tone(0.0, 1.2, SAW, 420.0, 36.0, 0.6, 0.002, 1.2, 0.5, 2400.0)
		_tone(0.0, 1.0, SINE, 140.0, 28.0, 0.9, 0.002, 1.2)
		_noise(0.0, 1.1, 0.8, 3000.0, 100.0, 0.0, 0.001, 1.6)
		_save(SFX_DIR, "player_death", 0.85)
	if _wanted("revive"):
		_begin("revive", 1.0)
		_tone(0.0, 0.5, SINE, 180.0, 1300.0, 0.4, 0.05, 1.0)
		_arp(0.25, [-9, -2, 3, 7, 10, 15], 0.07, 0.5, TRI, 0.45)
		_noise(0.0, 0.6, 0.15, 500.0, 9000.0, 400.0, 0.3, 1.2)
		_save(SFX_DIR, "revive", 0.8)
	if _wanted("phase"):
		_begin("phase", 0.3)
		_tone(0.0, 0.28, SINE, 1400.0, 2500.0, 0.6, 0.02, 1.4, 0.5, 0.0, 28.0, 0.06)
		_noise(0.0, 0.25, 0.15, 9000.0, 9000.0, 5000.0, 0.03, 1.5)
		_save(SFX_DIR, "phase", 0.5)

	# ---- events
	if _wanted("surge"):
		_begin("surge", 0.7)
		_tone(0.0, 0.3, SAW, 420.0, 680.0, 0.6, 0.01, 0.8, 0.5, 2600.0)
		_tone(0.34, 0.32, SAW, 420.0, 680.0, 0.6, 0.01, 1.0, 0.5, 2600.0)
		_save(SFX_DIR, "surge", 0.7)
	if _wanted("boss_warning"):
		_begin("boss_warning", 1.9)
		for k in 4:
			_tone(0.46 * float(k), 0.22, PULSE, 220.0, 220.0, 0.6, 0.01, 0.5, 0.5, 1800.0)
			_tone(0.46 * float(k) + 0.23, 0.22, PULSE, 277.0, 277.0, 0.6, 0.01, 0.5, 0.5, 1800.0)
		_tone(0.0, 1.85, SINE, 55.0, 55.0, 0.5, 0.2, 0.6)
		_save(SFX_DIR, "boss_warning", 0.8)
	if _wanted("boss_spawn"):
		_begin("boss_spawn", 1.4)
		_tone(0.0, 1.3, SINE, 78.0, 34.0, 1.0, 0.01, 1.0)
		_tone(0.0, 1.2, SAW, 110.0, 55.0, 0.35, 0.02, 1.2, 0.5, 900.0)
		_noise(0.0, 1.2, 0.7, 2600.0, 120.0, 0.0, 0.002, 1.5)
		_save(SFX_DIR, "boss_spawn", 0.85)
	if _wanted("boss_phase"):
		_begin("boss_phase", 0.8)
		_noise(0.0, 0.6, 1.0, 3000.0, 200.0, 0.0, 0.001, 1.8)
		_tone(0.0, 0.6, SINE, 105.0, 38.0, 1.0, 0.001, 1.4)
		for semis: int in [-21, -14, -9]:
			_tone(0.0, 0.5, SAW, _note(float(semis)), _note(float(semis)), 0.25, 0.002, 1.6, 0.5, 2400.0)
		_save(SFX_DIR, "boss_phase", 0.85)
	if _wanted("boss_charge"):
		_begin("boss_charge", 0.5)
		_tone(0.0, 0.45, SAW, 140.0, 640.0, 0.6, 0.03, 0.9, 0.5, 2800.0)
		_noise(0.0, 0.45, 0.5, 400.0, 5000.0, 200.0, 0.05, 1.2)
		_save(SFX_DIR, "boss_charge", 0.75)
	if _wanted("boss_laser"):
		_begin("boss_laser", 1.1)
		_tone(0.0, 1.05, SAW, 180.0, 176.0, 0.5, 0.05, 0.7, 0.5, 2400.0)
		_tone(0.0, 1.05, SAW, 181.6, 178.0, 0.5, 0.05, 0.7, 0.5, 2400.0)
		_tone(0.0, 1.05, SINE, 720.0, 700.0, 0.2, 0.08, 0.8, 0.5, 0.0, 40.0, 0.04)
		_noise(0.0, 0.9, 0.2, 5000.0, 5000.0, 2500.0, 0.05, 1.0)
		_save(SFX_DIR, "boss_laser", 0.75)
	if _wanted("boss_die"):
		_begin("boss_die", 2.2)
		_noise(0.0, 2.1, 1.0, 2600.0, 80.0, 0.0, 0.001, 1.5)
		_tone(0.0, 1.8, SAW, 520.0, 28.0, 0.5, 0.002, 1.2, 0.5, 2600.0)
		_tone(0.0, 1.6, SINE, 110.0, 26.0, 1.0, 0.002, 1.2)
		for k in 6:
			_noise(0.15 + 0.22 * float(k), 0.3, 0.5, 4000.0, 400.0, 0.0, 0.001, 2.0)
		_arp(0.5, [22, 19, 15, 10, 7, 3], 0.11, 0.5, TRI, 0.22)
		_save(SFX_DIR, "boss_die", 0.9)

	# ---- run bookends
	if _wanted("run_start"):
		_begin("run_start", 0.55)
		_tone(0.0, 0.25, SINE, 200.0, 800.0, 0.4, 0.02, 1.0)
		_tone(0.0, 0.22, TRI, _note(-2.0), _note(-2.0), 0.6, 0.002, 1.8)
		_tone(0.16, 0.36, TRI, _note(10.0), _note(10.0), 0.6, 0.002, 2.0)
		_save(SFX_DIR, "run_start", 0.7)
	if _wanted("victory"):
		_begin("victory", 1.5)
		_arp(0.0, [3, 7, 10, 15], 0.13, 0.4, PULSE, 0.4, 0.3, 4500.0)
		for semis: int in [3, 7, 10, 15]:
			_tone(0.52, 0.9, TRI, _note(float(semis)), _note(float(semis)), 0.3, 0.004, 1.6)
		_arp(0.52, [15, 19, 22, 27], 0.05, 0.6, SINE, 0.2)
		_save(SFX_DIR, "victory", 0.8)
	if _wanted("defeat"):
		_begin("defeat", 1.3)
		_tone(0.0, 0.3, SAW, _note(-2.0), _note(-2.0), 0.5, 0.004, 1.2, 0.5, 1800.0)
		_tone(0.26, 0.3, SAW, _note(-6.0), _note(-6.0), 0.5, 0.004, 1.2, 0.5, 1600.0)
		_tone(0.52, 0.75, SAW, _note(-9.0), _note(-10.0), 0.5, 0.004, 1.2, 0.5, 1300.0)
		_tone(0.52, 0.75, SINE, _note(-21.0), _note(-21.0), 0.6, 0.004, 1.2)
		_save(SFX_DIR, "defeat", 0.75)


# --------------------------------------------------------------------- music

## Chord roots and the scale tones played over them, as semitones from A4.
const PROGRESSION := [
	{"root": -24, "chord": [-12, -9, -5, 0]},   # A minor
	{"root": -28, "chord": [-16, -12, -9, -4]}, # F major
	{"root": -21, "chord": [-9, -5, -2, 3]},    # C major
	{"root": -26, "chord": [-14, -10, -7, -2]}, # G major
]


const ARP_PATTERN: PackedInt32Array = [0, 1, 2, 3, 2, 1, 3, 2]


func _make_music() -> void:
	if _wanted("music_menu"):
		_music_menu()
	if _wanted("music_combat"):
		_music_combat()


## Slow, wide pads with sparse plucks. One chord per two bars at 72 BPM.
func _music_menu() -> void:
	var beat := 60.0 / 72.0
	var chord_len := beat * 8.0
	var total := chord_len * 4.0
	_begin("music_menu", total, MUSIC_RATE, true)
	for c in 4:
		var entry: Dictionary = PROGRESSION[c]
		var at := chord_len * float(c)
		var chord: Array = entry.chord
		for semis: int in chord:
			var f := _note(float(semis))
			# Each pad note overlaps the next chord slightly for a seamless bed.
			_tone(at, chord_len * 1.08, SAW, f, f * 1.003, 0.16, chord_len * 0.3, 0.8, 0.5, 700.0)
			_tone(at, chord_len * 1.08, SAW, f * 0.997, f, 0.16, chord_len * 0.3, 0.8, 0.5, 700.0)
		var root := _note(float(entry.root))
		_tone(at, chord_len * 1.02, SINE, root, root, 0.4, 0.4, 0.7)
		for k in 6:
			var pick := int(chord[(k * 3 + c) % chord.size()]) + 12
			var f := _note(float(pick))
			_tone(at + beat * (1.0 + float(k) * 1.25), beat * 1.6, TRI, f, f, 0.14, 0.004, 2.4)
	_echo(beat * 0.75, 0.35, 0.3)
	_save(MUSIC_DIR, "music_menu", 0.75, true)


## Driving loop at 124 BPM: four-on-the-floor kick, off-beat hats, an eighth
## note bass and a sixteenth-note arpeggio. Four bars per chord.
func _music_combat() -> void:
	var beat := 60.0 / 124.0
	var bar := beat * 4.0
	var total := bar * 16.0
	_begin("music_combat", total, MUSIC_RATE, true)
	for b in 64:
		var at := beat * float(b)
		_tone(at, 0.22, SINE, 135.0, 42.0, 0.95, 0.001, 1.8)
		_noise(at, 0.02, 0.2, 5000.0, 2000.0, 800.0)
		_noise(at + beat * 0.5, 0.05, 0.22, 11000.0, 8000.0, 6000.0, 0.001, 2.0)
		if b % 4 == 2:
			# Backbeat clap.
			_noise(at, 0.14, 0.5, 3500.0, 1200.0, 900.0, 0.001, 2.0)
	for c in 4:
		var entry: Dictionary = PROGRESSION[c]
		var chord: Array = entry.chord
		var chord_at := bar * 4.0 * float(c)
		var root := _note(float(entry.root))
		for e in 32:
			var at := chord_at + beat * 0.5 * float(e)
			# Octave-bouncing bass, resting on each beat where the kick lands.
			if e % 2 == 1:
				var f := root * (2.0 if e % 8 == 7 else 1.0)
				_tone(at, beat * 0.42, SAW, f, f, 0.42, 0.003, 1.3, 0.5, 520.0)
		for s in 64:
			var at := chord_at + beat * 0.25 * float(s)
			var step: int = ARP_PATTERN[s % 8]
			@warning_ignore("integer_division")
			var semis := int(chord[step]) + (12 if (s / 8) % 2 == 1 else 0)
			var f := _note(float(semis))
			_tone(at, beat * 0.3, PULSE, f, f, 0.15, 0.002, 2.2, 0.25, 4200.0)
		# A sustained pad under the second half of each chord lifts the energy.
		for semis: int in chord:
			var f := _note(float(semis))
			_tone(chord_at + bar * 2.0, bar * 2.0, SAW, f, f * 1.004, 0.07, bar * 0.5, 0.6, 0.5, 1100.0)
	_echo(beat * 0.75, 0.3, 0.22)
	_save(MUSIC_DIR, "music_combat", 0.8, true)
