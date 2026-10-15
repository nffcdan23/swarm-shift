extends SceneTree
## Procedural art generator. Every sprite in the game is drawn here from signed
## distance shapes and written out as a plain PNG, so any of them can be replaced
## by hand-made art later without touching code.
##
## Usage:
##   godot --headless --path . --script res://tools/generate_art.gd
##   godot --headless --path . --script res://tools/generate_art.gd -- --only=enemy_swarmer,bolt
##   godot --headless --path . --script res://tools/generate_art.gd -- --sheet=/abs/path/contact.png
##
## Two sprite conventions:
##   MIX sprites    - full colour RGBA, drawn with normal alpha blending (enemies, pickups).
##   ENERGY sprites - white RGB with intensity in alpha, drawn additively and tinted at
##                    runtime; the shader turns the brightest part white-hot.

const ATLAS_DIR := "res://assets/sprites/atlas/"
const SPRITE_DIR := "res://assets/sprites/"
const BRAND_DIR := "res://assets/branding/"

const C_BG := Color("05070d")
const C_SWARMER := Color("ff4d6d")
const C_BRUTE := Color("ff9a3d")
const C_DASHER := Color("ffe14d")
const C_SHOOTER := Color("c77dff")
const C_SPLITTER := Color("7dff8a")
const C_TANK := Color("6fb7ff")
const C_ELITE := Color("ffd15c")
const C_BOSS := Color("ff3d6e")
const C_WEAVER := Color("5cf0ff")
const C_MORTAR := Color("ff8a5c")
const C_BOMBER := Color("ff6a3d")
# Run energy is always green, whatever the size of the crystal: green is
# "this run", gold is "yours to keep". Bigger crystals are brighter, not bluer.
const C_XP_S := Color("5cffb1")
const C_XP_M := Color("3dff8f")
const C_XP_L := Color("7dffbc")
const C_CREDIT := Color("ffd15c")
const C_REPAIR := Color("5cff8a")
const C_MAGNET := Color("ff4d5e")
const C_BOMB := Color("ff9a3d")
const C_HOLE := Color("9d6bff")
const C_CORE := Color("2de2ff")
const WHITE := Color(1, 1, 1, 1)

var POLY_SWARMER := PackedVector2Array([Vector2(0.62, 0.0), Vector2(-0.44, -0.42), Vector2(-0.2, 0.0), Vector2(-0.44, 0.42)])
var POLY_DASHER := PackedVector2Array([Vector2(0.64, 0.0), Vector2(-0.06, -0.3), Vector2(-0.5, -0.4), Vector2(-0.26, 0.0), Vector2(-0.5, 0.4), Vector2(-0.06, 0.3)])
var POLY_SHOOTER := PackedVector2Array([Vector2(0.6, 0.0), Vector2(0.0, -0.42), Vector2(-0.5, 0.0), Vector2(0.0, 0.42)])
var POLY_WEAVER := PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.02, -0.5), Vector2(-0.46, -0.56), Vector2(-0.1, -0.2), Vector2(-0.3, 0.0), Vector2(-0.1, 0.2), Vector2(-0.46, 0.56), Vector2(0.02, 0.5)])
var POLY_GEM_S := PackedVector2Array([Vector2(0.0, -0.52), Vector2(0.36, 0.0), Vector2(0.0, 0.52), Vector2(-0.36, 0.0)])
var POLY_MISSILE := PackedVector2Array([Vector2(0.58, 0.0), Vector2(0.26, -0.13), Vector2(-0.26, -0.13), Vector2(-0.5, -0.3), Vector2(-0.42, 0.0), Vector2(-0.5, 0.3), Vector2(-0.26, 0.13), Vector2(0.26, 0.13)])
var POLY_DRONE := PackedVector2Array([Vector2(0.56, 0.0), Vector2(-0.1, -0.2), Vector2(-0.4, -0.5), Vector2(-0.24, 0.0), Vector2(-0.4, 0.5), Vector2(-0.1, 0.2)])
var POLY_SHARD := PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.0, -0.13), Vector2(-0.62, 0.0), Vector2(0.0, 0.13)])
var POLY_CLAW := PackedVector2Array([Vector2(0.0, -0.96), Vector2(0.2, -0.72), Vector2(0.42, -0.74), Vector2(0.26, -0.6), Vector2(-0.3, -0.62), Vector2(-0.16, -0.76)])

# Premultiplied accumulator for the pixel currently being shaded.
var _r := 0.0
var _g := 0.0
var _b := 0.0
var _a := 0.0
var _fallback := Color.WHITE


func _init() -> void:
	var only := PackedStringArray()
	var sheet := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7).split(",")
		elif arg.begins_with("--sheet="):
			sheet = arg.substr(8)
	for dir in [ATLAS_DIR, SPRITE_DIR, BRAND_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var jobs := _jobs()
	var t0 := Time.get_ticks_msec()
	var made: Array = []
	for job: Dictionary in jobs:
		if not only.is_empty() and not only.has(job.name):
			continue
		var t1 := Time.get_ticks_msec()
		var img := _render(job)
		if job.has("upscale"):
			img.resize(job.upscale, job.upscale, Image.INTERPOLATE_LANCZOS)
		if job.get("opaque", false):
			img.convert(Image.FORMAT_RGB8)
		var path: String = job.dir + job.name + ".png"
		var err := img.save_png(path)
		if err != OK:
			push_error("Failed to save %s (%d)" % [path, err])
		made.append({"job": job, "img": img})
		print("  %-18s %4dpx  %5d ms" % [job.name, job.size, Time.get_ticks_msec() - t1])
	print("Generated %d sprites in %.1f s" % [made.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	if sheet != "":
		_write_sheet(made, sheet)
	quit()


func _jobs() -> Array:
	var j: Array = []
	# --- MIX sprites (atlas) ---
	j.append({"name": "enemy_swarmer", "size": 128, "dir": ATLAS_DIR, "fn": _spr_swarmer})
	j.append({"name": "enemy_dasher", "size": 128, "dir": ATLAS_DIR, "fn": _spr_dasher})
	j.append({"name": "enemy_shooter", "size": 128, "dir": ATLAS_DIR, "fn": _spr_shooter})
	j.append({"name": "enemy_splitter", "size": 128, "dir": ATLAS_DIR, "fn": _spr_splitter})
	j.append({"name": "enemy_splitling", "size": 128, "dir": ATLAS_DIR, "fn": _spr_splitling})
	j.append({"name": "enemy_weaver", "size": 128, "dir": ATLAS_DIR, "fn": _spr_weaver})
	j.append({"name": "enemy_mortar", "size": 128, "dir": ATLAS_DIR, "fn": _spr_mortar})
	j.append({"name": "enemy_bomber", "size": 128, "dir": ATLAS_DIR, "fn": _spr_bomber})
	j.append({"name": "enemy_brute", "size": 256, "dir": ATLAS_DIR, "fn": _spr_brute})
	j.append({"name": "enemy_tank", "size": 256, "dir": ATLAS_DIR, "fn": _spr_tank})
	j.append({"name": "elite_aura", "size": 256, "dir": ATLAS_DIR, "fn": _spr_elite_aura})
	j.append({"name": "hole", "size": 256, "dir": ATLAS_DIR, "fn": _spr_hole})
	j.append({"name": "gem_s", "size": 128, "dir": ATLAS_DIR, "fn": _spr_gem_s})
	j.append({"name": "gem_m", "size": 128, "dir": ATLAS_DIR, "fn": _spr_gem_m})
	j.append({"name": "gem_l", "size": 128, "dir": ATLAS_DIR, "fn": _spr_gem_l})
	j.append({"name": "credit", "size": 128, "dir": ATLAS_DIR, "fn": _spr_credit})
	j.append({"name": "repair", "size": 128, "dir": ATLAS_DIR, "fn": _spr_repair})
	j.append({"name": "magnet", "size": 128, "dir": ATLAS_DIR, "fn": _spr_magnet})
	j.append({"name": "bomb", "size": 128, "dir": ATLAS_DIR, "fn": _spr_bomb})
	j.append({"name": "cache", "size": 128, "dir": ATLAS_DIR, "fn": _spr_cache})
	# --- ENERGY sprites (atlas) ---
	j.append({"name": "bolt", "size": 128, "dir": ATLAS_DIR, "fn": _spr_bolt, "energy": true})
	j.append({"name": "pellet", "size": 128, "dir": ATLAS_DIR, "fn": _spr_pellet, "energy": true})
	j.append({"name": "orb", "size": 128, "dir": ATLAS_DIR, "fn": _spr_orb, "energy": true})
	j.append({"name": "glow", "size": 128, "dir": ATLAS_DIR, "fn": _spr_glow, "energy": true})
	j.append({"name": "flare", "size": 128, "dir": ATLAS_DIR, "fn": _spr_flare, "energy": true})
	j.append({"name": "missile", "size": 128, "dir": ATLAS_DIR, "fn": _spr_missile, "energy": true})
	j.append({"name": "blade", "size": 128, "dir": ATLAS_DIR, "fn": _spr_blade, "energy": true})
	j.append({"name": "mine", "size": 128, "dir": ATLAS_DIR, "fn": _spr_mine, "energy": true})
	j.append({"name": "drone", "size": 128, "dir": ATLAS_DIR, "fn": _spr_drone, "energy": true})
	j.append({"name": "beam", "size": 128, "dir": ATLAS_DIR, "fn": _spr_beam, "energy": true, "window": false})
	j.append({"name": "shard", "size": 128, "dir": ATLAS_DIR, "fn": _spr_shard, "energy": true})
	j.append({"name": "bullet", "size": 128, "dir": ATLAS_DIR, "fn": _spr_bullet, "energy": true})
	# --- Standalone sprites ---
	j.append({"name": "player_core", "size": 256, "dir": SPRITE_DIR, "fn": _spr_player_core})
	j.append({"name": "player_ring", "size": 256, "dir": SPRITE_DIR, "fn": _spr_player_ring, "energy": true})
	j.append({"name": "boss_core", "size": 512, "dir": SPRITE_DIR, "fn": _spr_boss_core})
	j.append({"name": "boss_ring", "size": 512, "dir": SPRITE_DIR, "fn": _spr_boss_ring})
	j.append({"name": "boss_shell", "size": 512, "dir": SPRITE_DIR, "fn": _spr_boss_shell})
	# --- Branding ---
	j.append({"name": "icon", "size": 512, "upscale": 1024, "dir": BRAND_DIR, "fn": _spr_icon, "window": false, "opaque": true})
	j.append({"name": "splash", "size": 512, "dir": BRAND_DIR, "fn": _spr_splash, "window": false})
	return j


func _render(job: Dictionary) -> Image:
	var size: int = job.size
	var fn: Callable = job.fn
	var use_window: bool = job.get("window", true)
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var px := 2.0 / float(size)
	for y in size:
		var py := (float(y) + 0.5) * px - 1.0
		for x in size:
			var p := Vector2((float(x) + 0.5) * px - 1.0, py)
			var c: Color = fn.call(p, px)
			if use_window:
				c.a *= smoothstep(1.0, 0.8, p.length())
			img.set_pixel(x, y, c)
	return img


# ---------------------------------------------------------------- SDF toolkit

func sd_circle(p: Vector2, r: float) -> float:
	return p.length() - r


func sd_box(p: Vector2, b: Vector2) -> float:
	var d := p.abs() - b
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)


func sd_rbox(p: Vector2, b: Vector2, r: float) -> float:
	return sd_box(p, b - Vector2(r, r)) - r


func sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


## Regular polygon with circumradius r; one vertex sits at vertex_angle.
func sd_ngon(p: Vector2, r: float, n: int, vertex_angle: float) -> float:
	var s := TAU / float(n)
	var th := atan2(p.y, p.x) - vertex_angle - s * 0.5
	th = fposmod(th + s * 0.5, s) - s * 0.5
	var l := p.length()
	var dx := l * cos(th) - r * cos(PI / float(n))
	var dy := absf(l * sin(th)) - r * sin(PI / float(n))
	if dy <= 0.0:
		return dx
	return Vector2(maxf(dx, 0.0), dy).length()


## Arbitrary simple polygon (Inigo Quilez' winding-parity formulation).
func sd_poly(p: Vector2, v: PackedVector2Array) -> float:
	var n := v.size()
	var d := (p - v[0]).length_squared()
	var s := 1.0
	var j := n - 1
	for i in n:
		var e := v[j] - v[i]
		var w := p - v[i]
		var b := w - e * clampf(w.dot(e) / e.dot(e), 0.0, 1.0)
		d = minf(d, b.length_squared())
		var c1 := p.y >= v[i].y
		var c2 := p.y < v[j].y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			s = -s
		j = i
	return s * sqrt(d)


func sd_star(p: Vector2, r_out: float, r_in: float, n: int, rot: float) -> float:
	# Fold into one sector, then measure against the tip->notch edge.
	var s := TAU / float(n)
	var th := atan2(p.y, p.x) - rot
	th = absf(fposmod(th + s * 0.5, s) - s * 0.5)
	var l := p.length()
	var q := Vector2(l * cos(th), l * sin(th))
	var a := Vector2(r_out, 0.0)
	var b := Vector2(r_in * cos(s * 0.5), r_in * sin(s * 0.5))
	var dist := sd_segment(q, a, b)
	var e := b - a
	var w := q - a
	return dist if (e.x * w.y - e.y * w.x) < 0.0 else -dist


func rot(p: Vector2, a: float) -> Vector2:
	var c := cos(a)
	var s := sin(a)
	return Vector2(p.x * c + p.y * s, -p.x * s + p.y * c)


func mask(d: float, px: float) -> float:
	return smoothstep(px * 1.3, -px * 1.3, d)


# ------------------------------------------------------------ pixel shading

func px_reset(fallback: Color) -> void:
	_r = 0.0
	_g = 0.0
	_b = 0.0
	_a = 0.0
	_fallback = fallback


func px_over(col: Color, a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	_r = col.r * a + _r * (1.0 - a)
	_g = col.g * a + _g * (1.0 - a)
	_b = col.b * a + _b * (1.0 - a)
	_a = a + _a * (1.0 - a)


func px_add(col: Color, a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	_r += col.r * a
	_g += col.g * a
	_b += col.b * a
	_a = maxf(_a, a)


func px_out() -> Color:
	if _a < 0.002:
		return Color(_fallback.r, _fallback.g, _fallback.b, 0.0)
	return Color(minf(_r / _a, 1.0), minf(_g / _a, 1.0), minf(_b / _a, 1.0), minf(_a, 1.0))


## The house style: dark tinted interior, bright rim, soft outer halo.
func neon(d: float, px: float, col: Color, rim_w: float = 0.04, glow_w: float = 0.11, fill: float = 0.2, glow_i: float = 0.8) -> void:
	var inside := mask(d, px)
	var rim := exp(-(d * d) / (rim_w * rim_w))
	var glow := exp(-maxf(d, 0.0) / glow_w) * glow_i
	px_over(col, glow * (1.0 - inside))
	var depth := clampf(-d / 0.3, 0.0, 1.0)
	var k := fill + 0.32 * (1.0 - depth) * (1.0 - depth)
	px_over(Color(col.r * k, col.g * k, col.b * k), inside * 0.95)
	px_add(col.lerp(WHITE, 0.62), rim)


## Energy sprite: white RGB, intensity in alpha.
func energy(intensity: float) -> Color:
	return Color(1.0, 1.0, 1.0, clampf(intensity, 0.0, 1.0))


func solid_glow(d: float, px: float, glow_w: float, glow_i: float) -> float:
	return maxf(mask(d, px), exp(-maxf(d, 0.0) / glow_w) * glow_i)


# ------------------------------------------------------------------ enemies

func _spr_swarmer(p: Vector2, px: float) -> Color:
	px_reset(C_SWARMER)
	var d := sd_poly(p, POLY_SWARMER) - 0.03
	neon(d, px, C_SWARMER)
	px_add(Color(1.0, 0.92, 0.94), mask(sd_circle(p - Vector2(0.13, 0.0), 0.085), px) * 0.95)
	return px_out()


func _spr_dasher(p: Vector2, px: float) -> Color:
	px_reset(C_DASHER)
	var d := sd_poly(p, POLY_DASHER) - 0.025
	neon(d, px, C_DASHER, 0.035, 0.1)
	# Bright spine so it reads as fast and directional.
	var spine := sd_segment(p, Vector2(-0.12, 0.0), Vector2(0.44, 0.0)) - 0.03
	px_add(Color(1.0, 0.98, 0.85), mask(spine, px) * 0.9)
	return px_out()


func _spr_shooter(p: Vector2, px: float) -> Color:
	px_reset(C_SHOOTER)
	var d := sd_poly(p, POLY_SHOOTER) - 0.03
	neon(d, px, C_SHOOTER)
	var eye_ring := absf(sd_circle(p - Vector2(0.02, 0.0), 0.17)) - 0.028
	px_add(C_SHOOTER.lerp(WHITE, 0.7), mask(eye_ring, px) * 0.9)
	px_add(WHITE, mask(sd_circle(p - Vector2(0.02, 0.0), 0.07), px))
	return px_out()


func _spr_splitter(p: Vector2, px: float) -> Color:
	px_reset(C_SPLITTER)
	var d := sd_rbox(p, Vector2(0.47, 0.47), 0.12)
	var gap := minf(absf(p.x), absf(p.y)) - 0.045
	d = maxf(d, -gap)
	neon(d, px, C_SPLITTER, 0.035, 0.1, 0.24)
	return px_out()


func _spr_splitling(p: Vector2, px: float) -> Color:
	px_reset(C_SPLITTER)
	var d := sd_rbox(rot(p, PI * 0.25), Vector2(0.4, 0.4), 0.1)
	neon(d, px, C_SPLITTER, 0.05, 0.12, 0.3)
	px_add(Color(0.92, 1.0, 0.94), mask(sd_circle(p, 0.1), px) * 0.9)
	return px_out()


## A swept crescent: reads as something that travels sideways.
func _spr_weaver(p: Vector2, px: float) -> Color:
	px_reset(C_WEAVER)
	var d := sd_poly(p, POLY_WEAVER) - 0.02
	neon(d, px, C_WEAVER, 0.035, 0.1, 0.22)
	px_add(Color(0.9, 1.0, 1.0), mask(sd_circle(p - Vector2(0.2, 0.0), 0.075), px) * 0.95)
	return px_out()


## A squat emplacement with a barrel: it stands off and fires over the swarm.
func _spr_mortar(p: Vector2, px: float) -> Color:
	px_reset(C_MORTAR)
	var body := sd_ngon(p - Vector2(-0.08, 0.0), 0.5, 6, 0.0)
	var barrel := sd_rbox(p - Vector2(0.4, 0.0), Vector2(0.2, 0.11), 0.04)
	var d := minf(body, barrel)
	neon(d, px, C_MORTAR, 0.04, 0.11, 0.24)
	var bore := absf(sd_circle(p - Vector2(-0.08, 0.0), 0.2)) - 0.03
	px_add(C_MORTAR.lerp(WHITE, 0.7), mask(bore, px) * 0.9)
	px_add(WHITE, mask(sd_circle(p - Vector2(-0.08, 0.0), 0.08), px))
	return px_out()


## A spiked mine with a hot core: the one enemy that should look like a bomb.
func _spr_bomber(p: Vector2, px: float) -> Color:
	px_reset(C_BOMBER)
	var d := sd_star(p, 0.6, 0.38, 6, 0.0) - 0.02
	neon(d, px, C_BOMBER, 0.04, 0.12, 0.3, 0.95)
	var ring := absf(sd_circle(p, 0.2)) - 0.03
	px_add(C_BOMBER.lerp(WHITE, 0.75), mask(ring, px) * 0.9)
	px_add(Color(1.0, 0.97, 0.8), mask(sd_circle(p, 0.1), px))
	return px_out()


func _spr_brute(p: Vector2, px: float) -> Color:
	px_reset(C_BRUTE)
	var d := sd_ngon(p, 0.62, 6, 0.0)
	neon(d, px, C_BRUTE, 0.035, 0.1, 0.18)
	var inner := sd_ngon(p, 0.34, 6, PI / 6.0)
	px_over(C_BRUTE * 0.55, mask(inner, px) * 0.9)
	px_add(C_BRUTE.lerp(WHITE, 0.6), exp(-(inner * inner) / (0.022 * 0.022)))
	# Six struts joining the core to the shell.
	var a := fposmod(atan2(p.y, p.x) + PI / 6.0, PI / 3.0) - PI / 6.0
	var l := p.length()
	var strut := absf(l * sin(a)) - 0.022
	if l > 0.3 and l < 0.52:
		px_add(C_BRUTE.lerp(WHITE, 0.3), mask(strut, px) * 0.6)
	px_add(WHITE, mask(sd_circle(p, 0.09), px) * 0.9)
	return px_out()


func _spr_tank(p: Vector2, px: float) -> Color:
	px_reset(C_TANK)
	var d := sd_ngon(p, 0.63, 8, PI / 8.0)
	neon(d, px, C_TANK, 0.045, 0.1, 0.16)
	var plate := sd_ngon(p, 0.5, 8, PI / 8.0)
	px_add(C_TANK.lerp(WHITE, 0.4), exp(-(plate * plate) / (0.016 * 0.016)) * 0.7)
	var ring := absf(sd_circle(p, 0.3)) - 0.035
	px_add(C_TANK.lerp(WHITE, 0.6), mask(ring, px) * 0.9)
	for i in 4:
		var ang := PI * 0.25 + float(i) * PI * 0.5
		var bolt := sd_circle(p - Vector2(cos(ang), sin(ang)) * 0.4, 0.045)
		px_add(WHITE, mask(bolt, px) * 0.85)
	px_add(WHITE, mask(sd_circle(p, 0.12), px))
	return px_out()


func _spr_elite_aura(p: Vector2, px: float) -> Color:
	px_reset(C_ELITE)
	var d := sd_star(p, 0.9, 0.72, 12, 0.0)
	px_over(C_ELITE, exp(-absf(d) / 0.07) * 0.55)
	px_add(C_ELITE.lerp(WHITE, 0.5), exp(-(d * d) / (0.022 * 0.022)))
	return px_out()


func _spr_hole(p: Vector2, px: float) -> Color:
	px_reset(C_HOLE)
	var l := p.length()
	var th := atan2(p.y, p.x)
	var swirl := 0.55 + 0.45 * sin(th * 3.0 + l * 11.0)
	var halo := exp(-maxf(l - 0.4, 0.0) / 0.16) * swirl
	px_over(C_HOLE, halo * 0.9)
	px_over(Color(0.01, 0.0, 0.03), mask(l - 0.4, px))
	var rim := l - 0.41
	px_add(C_HOLE.lerp(WHITE, 0.75), exp(-(rim * rim) / (0.03 * 0.03)))
	return px_out()


# ------------------------------------------------------------------ pickups

func _gem_highlight(p: Vector2, d: float, px: float) -> void:
	var facet := smoothstep(0.15, -0.5, p.x * 0.6 + p.y)
	px_add(WHITE, mask(d + 0.07, px) * facet * 0.55)


func _spr_gem_s(p: Vector2, px: float) -> Color:
	px_reset(C_XP_S)
	var d := sd_poly(p, POLY_GEM_S) - 0.03
	neon(d, px, C_XP_S, 0.045, 0.13, 0.5, 0.9)
	_gem_highlight(p, d, px)
	return px_out()


func _spr_gem_m(p: Vector2, px: float) -> Color:
	px_reset(C_XP_M)
	var d := sd_ngon(p * Vector2(1.18, 1.0), 0.55, 6, PI * 0.5)
	neon(d, px, C_XP_M, 0.045, 0.13, 0.5, 0.9)
	_gem_highlight(p, d, px)
	return px_out()


func _spr_gem_l(p: Vector2, px: float) -> Color:
	px_reset(C_XP_L)
	var d := sd_ngon(p, 0.58, 8, PI / 8.0)
	neon(d, px, C_XP_L, 0.05, 0.14, 0.5, 1.0)
	_gem_highlight(p, d, px)
	px_add(WHITE, mask(sd_star(p, 0.3, 0.1, 4, PI * 0.25), px) * 0.9)
	return px_out()


func _spr_credit(p: Vector2, px: float) -> Color:
	px_reset(C_CREDIT)
	var d := sd_ngon(p, 0.56, 6, PI * 0.5)
	neon(d, px, C_CREDIT, 0.045, 0.12, 0.45, 0.9)
	var inner := sd_ngon(p, 0.36, 6, PI * 0.5)
	px_add(C_CREDIT.lerp(WHITE, 0.6), exp(-(inner * inner) / (0.02 * 0.02)) * 0.9)
	px_add(WHITE, mask(sd_rbox(p, Vector2(0.045, 0.19), 0.03), px) * 0.95)
	return px_out()


func _spr_repair(p: Vector2, px: float) -> Color:
	px_reset(C_REPAIR)
	var d := sd_circle(p, 0.54)
	neon(d, px, C_REPAIR, 0.045, 0.12, 0.3, 0.9)
	var cross := minf(sd_rbox(p, Vector2(0.3, 0.1), 0.03), sd_rbox(p, Vector2(0.1, 0.3), 0.03))
	px_add(WHITE, mask(cross, px))
	return px_out()


func _spr_magnet(p: Vector2, px: float) -> Color:
	px_reset(C_MAGNET)
	var q := p - Vector2(0.0, -0.06)
	var arc := maxf(absf(q.length() - 0.33) - 0.13, q.y)
	var legs := minf(sd_box(q - Vector2(-0.33, 0.17), Vector2(0.13, 0.17)), sd_box(q - Vector2(0.33, 0.17), Vector2(0.13, 0.17)))
	var d := minf(arc, legs)
	neon(d, px, C_MAGNET, 0.045, 0.12, 0.5, 0.9)
	var tips := minf(sd_box(q - Vector2(-0.33, 0.36), Vector2(0.13, 0.085)), sd_box(q - Vector2(0.33, 0.36), Vector2(0.13, 0.085)))
	px_over(WHITE, mask(tips, px))
	return px_out()


func _spr_bomb(p: Vector2, px: float) -> Color:
	px_reset(C_BOMB)
	var d := sd_star(p, 0.64, 0.4, 8, 0.0)
	neon(d, px, C_BOMB, 0.04, 0.12, 0.45, 0.95)
	px_add(WHITE, mask(sd_circle(p, 0.2), px))
	return px_out()


func _spr_cache(p: Vector2, px: float) -> Color:
	px_reset(C_ELITE)
	var d := sd_rbox(p, Vector2(0.56, 0.44), 0.1)
	neon(d, px, C_ELITE, 0.045, 0.14, 0.4, 1.0)
	var band := absf(p.y + 0.06) - 0.03
	px_add(C_ELITE.lerp(WHITE, 0.6), mask(maxf(band, d + 0.02), px) * 0.9)
	px_add(WHITE, mask(sd_ngon(p - Vector2(0.0, -0.06), 0.15, 4, 0.0), px))
	return px_out()


# ----------------------------------------------------------- energy sprites

func _spr_bolt(p: Vector2, _px: float) -> Color:
	# Tapered capsule: fat bright head, thin tail.
	var t := clampf((p.x + 0.5) / 1.0, 0.0, 1.0)
	var width := lerpf(0.022, 0.085, t * t)
	var d := sd_segment(p, Vector2(-0.5, 0.0), Vector2(0.46, 0.0)) - width
	var core := smoothstep(0.02, -0.02, d)
	var halo := exp(-maxf(d, 0.0) / 0.075) * 0.62 * (0.35 + 0.65 * t)
	return energy(maxf(core, halo))


func _spr_pellet(p: Vector2, _px: float) -> Color:
	var t := clampf((p.x + 0.3) / 0.6, 0.0, 1.0)
	var d := sd_segment(p, Vector2(-0.3, 0.0), Vector2(0.24, 0.0)) - lerpf(0.03, 0.12, t)
	return energy(maxf(smoothstep(0.02, -0.02, d), exp(-maxf(d, 0.0) / 0.1) * 0.6))


func _spr_orb(p: Vector2, _px: float) -> Color:
	var d := sd_circle(p, 0.26)
	return energy(maxf(smoothstep(0.03, -0.03, d), exp(-maxf(d, 0.0) / 0.15) * 0.7))


func _spr_glow(p: Vector2, _px: float) -> Color:
	var l := clampf(1.0 - p.length(), 0.0, 1.0)
	return energy(pow(l, 2.3) * 0.68)


func _spr_flare(p: Vector2, _px: float) -> Color:
	var h := exp(-absf(p.x) / 0.26) * exp(-(p.y * p.y) / (0.028 * 0.028))
	var v := exp(-absf(p.y) / 0.26) * exp(-(p.x * p.x) / (0.028 * 0.028))
	var core := exp(-p.length_squared() / (0.11 * 0.11))
	return energy(maxf(maxf(h, v), core))


func _spr_missile(p: Vector2, px: float) -> Color:
	var d := sd_poly(p, POLY_MISSILE) - 0.02
	var body := mask(d, px) * 0.66
	var nose := mask(sd_circle(p - Vector2(0.3, 0.0), 0.1), px)
	return energy(maxf(maxf(body, nose), exp(-maxf(d, 0.0) / 0.09) * 0.5))


func _spr_blade(p: Vector2, px: float) -> Color:
	var d := maxf(sd_circle(p, 0.62), -sd_circle(p - Vector2(0.3, 0.0), 0.66))
	var edge := exp(-(d * d) / (0.035 * 0.035))
	return energy(maxf(maxf(mask(d, px) * 0.6, edge), exp(-maxf(d, 0.0) / 0.1) * 0.5))


func _spr_mine(p: Vector2, px: float) -> Color:
	var l := p.length()
	var ring := absf(l - 0.34) - 0.045
	var a := fposmod(atan2(p.y, p.x) + PI / 6.0, PI / 3.0) - PI / 6.0
	var spike := maxf(absf(l * sin(a)) - 0.035, maxf(0.36 - l, l - 0.58))
	var d := minf(ring, spike)
	var core := mask(sd_circle(p, 0.13), px)
	return energy(maxf(maxf(mask(d, px) * 0.68, core), exp(-maxf(d, 0.0) / 0.09) * 0.45))


func _spr_drone(p: Vector2, px: float) -> Color:
	var d := sd_poly(p, POLY_DRONE) - 0.02
	var core := mask(sd_circle(p - Vector2(0.06, 0.0), 0.1), px)
	var edge := exp(-(d * d) / (0.03 * 0.03)) * 0.69
	return energy(maxf(maxf(maxf(mask(d, px) * 0.42, edge), core), exp(-maxf(d, 0.0) / 0.09) * 0.45))


func _spr_beam(p: Vector2, _px: float) -> Color:
	# Constant along X so it can be stretched to any length.
	var core := smoothstep(0.16, 0.05, absf(p.y))
	var halo := exp(-(p.y * p.y) / (0.3 * 0.3)) * 0.55
	return energy(maxf(core, halo) * smoothstep(1.0, 0.86, absf(p.y)))


func _spr_shard(p: Vector2, px: float) -> Color:
	var d := sd_poly(p, POLY_SHARD)
	return energy(maxf(mask(d, px), exp(-maxf(d, 0.0) / 0.08) * 0.55))


func _spr_bullet(p: Vector2, px: float) -> Color:
	var l := p.length()
	var core := mask(l - 0.24, px)
	var ring := exp(-pow((l - 0.44) / 0.05, 2.0)) * 0.66
	return energy(maxf(maxf(core, ring), exp(-maxf(l - 0.24, 0.0) / 0.16) * 0.5))


# ----------------------------------------------------------- player and boss

func _spr_player_core(p: Vector2, px: float) -> Color:
	# Greyscale so it can be tinted per core / skin at runtime.
	var tint := Color(0.86, 0.86, 0.86)
	px_reset(tint)
	var shell := sd_ngon(p, 0.56, 6, PI * 0.5)
	neon(shell, px, tint, 0.04, 0.12, 0.16, 0.85)
	var orb := sd_circle(p, 0.3)
	var l := clampf(1.0 - p.length() / 0.3, 0.0, 1.0)
	px_over(Color(0.55, 0.55, 0.55).lerp(WHITE, l), mask(orb, px))
	px_add(WHITE, exp(-(orb * orb) / (0.03 * 0.03)) * 0.8)
	return px_out()


func _spr_player_ring(p: Vector2, px: float) -> Color:
	var l := p.length()
	var th := atan2(p.y, p.x)
	var seg := fposmod(th, TAU / 3.0)
	var gap := smoothstep(0.2, 0.32, seg) * smoothstep(TAU / 3.0, TAU / 3.0 - 0.12, seg)
	var ring := absf(l - 0.78) - 0.022
	var node_a := fposmod(th + TAU / 6.0, TAU / 3.0) - TAU / 6.0
	var node := sd_circle(Vector2(l * cos(node_a), l * sin(node_a)) - Vector2(0.78, 0.0), 0.05)
	var i := maxf(mask(ring, px) * gap, exp(-maxf(ring, 0.0) / 0.05) * 0.35 * gap)
	i = maxf(i, mask(node, px))
	return energy(i)


func _spr_boss_core(p: Vector2, px: float) -> Color:
	px_reset(C_BOSS)
	var d := sd_ngon(p, 0.56, 6, 0.0)
	neon(d, px, C_BOSS, 0.03, 0.12, 0.16, 0.9)
	var plate := sd_ngon(p, 0.44, 6, 0.0)
	px_add(C_BOSS.lerp(WHITE, 0.45), exp(-(plate * plate) / (0.012 * 0.012)) * 0.75)
	# Radial vents.
	var a := fposmod(atan2(p.y, p.x), PI / 3.0) - PI / 6.0
	var l := p.length()
	if l > 0.27 and l < 0.42:
		px_add(C_BOSS.lerp(WHITE, 0.3), mask(absf(l * sin(a)) - 0.014, px) * 0.7)
	# The eye: dark socket, bright iris, white-hot pupil.
	px_over(Color(0.06, 0.0, 0.02), mask(sd_circle(p, 0.25), px))
	var iris := absf(sd_circle(p, 0.2)) - 0.022
	px_add(C_BOSS.lerp(WHITE, 0.55), mask(iris, px))
	px_add(C_BOSS, exp(-maxf(sd_circle(p, 0.09), 0.0) / 0.06) * 0.8)
	px_add(WHITE, mask(sd_circle(p, 0.095), px))
	return px_out()


func _spr_boss_ring(p: Vector2, px: float) -> Color:
	px_reset(C_BOSS)
	var l := p.length()
	var th := atan2(p.y, p.x)
	var s := TAU / 6.0
	var seg := fposmod(th, s)
	var gap := smoothstep(0.1, 0.16, seg) * smoothstep(s - 0.1, s - 0.16, seg)
	var ring := absf(l - 0.72) - 0.035
	var inside := mask(ring, px) * gap
	px_over(C_BOSS, exp(-maxf(ring, 0.0) / 0.06) * 0.6 * gap)
	px_over(C_BOSS * 0.4, inside)
	px_add(C_BOSS.lerp(WHITE, 0.6), exp(-(ring * ring) / (0.014 * 0.014)) * gap)
	# Emitter nodes sitting in the gaps.
	var na := fposmod(th + s * 0.5, s) - s * 0.5
	var node := sd_circle(Vector2(l * cos(na), l * sin(na)) - Vector2(0.72, 0.0), 0.045)
	px_add(WHITE, mask(node, px))
	px_add(C_BOSS, exp(-maxf(node, 0.0) / 0.04) * 0.7)
	return px_out()


func _spr_boss_shell(p: Vector2, px: float) -> Color:
	px_reset(C_BOSS)
	# Three claws, 120 degrees apart.
	var th := atan2(p.y, p.x)
	var s := TAU / 3.0
	var k := floorf((th + PI * 0.5 + s * 0.5) / s)
	var q := rot(p, k * s)
	var d := sd_poly(q, POLY_CLAW) - 0.015
	neon(d, px, C_BOSS, 0.022, 0.07, 0.22, 0.85)
	return px_out()


# ----------------------------------------------------------------- branding

func _brand_scene(p: Vector2, px: float, with_swarm: bool) -> Color:
	# Background: deep navy vignette with a faint grid.
	var l := p.length()
	var bg := Color("0b1424").lerp(C_BG, clampf(l / 1.25, 0.0, 1.0))
	var gx := absf(fposmod(p.x * 5.0 + 0.5, 1.0) - 0.5)
	var gy := absf(fposmod(p.y * 5.0 + 0.5, 1.0) - 0.5)
	var grid := smoothstep(0.03, 0.0, minf(gx, gy)) * 0.1 * (1.0 - clampf(l, 0.0, 1.0))
	bg = bg.lerp(C_CORE, grid)
	px_reset(bg)
	px_over(bg, 1.0)
	# Core halo.
	px_add(C_CORE, exp(-l / 0.34) * 0.5)
	if with_swarm:
		for i in 7:
			var ang := TAU * float(i) / 7.0 + 0.35
			var dist := 0.66 + 0.06 * sin(float(i) * 2.4)
			var c := Vector2(cos(ang), sin(ang)) * dist
			var q := rot(p - c, ang + PI) / 0.2
			var d := (sd_poly(q, POLY_SWARMER) - 0.03) * 0.2
			var inside := mask(d, px)
			px_add(C_SWARMER, exp(-maxf(d, 0.0) / 0.03) * 0.75 * (1.0 - inside))
			px_over(C_SWARMER * 0.35, inside * 0.95)
			px_add(C_SWARMER.lerp(WHITE, 0.6), exp(-(d * d) / (0.011 * 0.011)))
	# Ring with three gaps.
	var th := atan2(p.y, p.x)
	var seg := fposmod(th + 0.5, TAU / 3.0)
	var gap := smoothstep(0.16, 0.26, seg) * smoothstep(TAU / 3.0, TAU / 3.0 - 0.1, seg)
	var ring := absf(l - 0.4) - 0.016
	px_add(C_CORE.lerp(WHITE, 0.5), maxf(mask(ring, px), exp(-maxf(ring, 0.0) / 0.03) * 0.5) * gap)
	# Hex shell and orb.
	var shell := sd_ngon(p, 0.27, 6, PI * 0.5)
	var inside_shell := mask(shell, px)
	px_over(C_CORE * 0.22, inside_shell * 0.95)
	px_add(C_CORE.lerp(WHITE, 0.6), exp(-(shell * shell) / (0.014 * 0.014)))
	var orb := sd_circle(p, 0.14)
	px_over(C_CORE.lerp(WHITE, clampf(1.0 - l / 0.14, 0.0, 1.0)), mask(orb, px))
	px_add(WHITE, exp(-maxf(orb, 0.0) / 0.05) * 0.5)
	var out := px_out()
	out.a = 1.0
	return out


func _spr_icon(p: Vector2, px: float) -> Color:
	return _brand_scene(p, px, true)


func _spr_splash(p: Vector2, px: float) -> Color:
	var c := _brand_scene(p * 1.9, px * 1.9, false)
	# Fade to the boot background colour so the image has no visible edge.
	var edge := smoothstep(0.42, 0.52, p.length())
	return c.lerp(C_BG, edge)


# -------------------------------------------------------------- contact sheet

func _write_sheet(made: Array, path: String) -> void:
	var cell := 144
	var cols := 8
	var rows := int(ceil(float(made.size()) / float(cols)))
	var sheet := Image.create_empty(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(C_BG)
	var tints := {"bolt": Color("2de2ff"), "pellet": Color("ff9a3d"), "orb": Color("5cffb1"), "glow": Color("2de2ff"), "flare": Color("ffe14d"),
		"missile": Color("ff6b4d"), "blade": Color("5cffb1"), "mine": Color("ff5cd6"), "drone": Color("ffe14d"), "beam": Color("ff4d9d"),
		"shard": Color("8fd8ff"), "bullet": Color("ff5a3d"), "player_ring": Color("2de2ff"), "player_core": Color("2de2ff")}
	for i in made.size():
		var job: Dictionary = made[i].job
		var src: Image = made[i].img.duplicate()
		if src.get_format() != Image.FORMAT_RGBA8:
			src.convert(Image.FORMAT_RGBA8)
		src.resize(cell - 16, cell - 16, Image.INTERPOLATE_LANCZOS)
		var ox := (i % cols) * cell + 8
		var oy := (i / cols) * cell + 8
		var is_energy: bool = job.get("energy", false)
		var tint: Color = tints.get(job.name, Color.WHITE)
		for y in src.get_height():
			for x in src.get_width():
				var s := src.get_pixel(x, y)
				var d := sheet.get_pixel(ox + x, oy + y)
				var o: Color
				if is_energy:
					var hot := smoothstep(0.7, 1.0, s.a)
					var c := tint.lerp(Color.WHITE, hot * 0.85)
					o = Color(minf(d.r + c.r * s.a, 1.0), minf(d.g + c.g * s.a, 1.0), minf(d.b + c.b * s.a, 1.0), 1.0)
				else:
					var sc := Color(s.r * tint.r, s.g * tint.g, s.b * tint.b)
					o = Color(lerpf(d.r, sc.r, s.a), lerpf(d.g, sc.g, s.a), lerpf(d.b, sc.b, s.a), 1.0)
				sheet.set_pixel(ox + x, oy + y, o)
	sheet.save_png(path)
	print("Contact sheet: ", path)
