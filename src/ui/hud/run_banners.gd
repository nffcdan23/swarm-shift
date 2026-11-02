class_name RunBanners
extends Control
## The one place in-run notifications appear: a compact banner directly below
## the HUD, one at a time, for synergies and for everything the run announces
## (sector titles, swarm surges, elites, mutators, boss warnings, boss phases).
##
## It lives in the HUD's column, so it sits below the top row and the boss bar
## whatever the screen, notch or safe area. Nothing in it takes input, and it
## is only ever a view: the run never waits for it.
##
## Queueing rules:
##   - One banner at a time, so nothing overlaps.
##   - A notice with the same title as one on screen or waiting is merged.
##   - Boss notices go to the front. Others wait their turn.
##   - An announcement is about a moment, so it is dropped if it has waited
##     longer than STALE_AFTER. A synergy is a reward, so it is never dropped.
##   - With others waiting, the banner on screen is cut short.
##   - While `holds` says so (an upgrade screen or the pause menu is up, and
##     would hide it), the queue waits, so a synergy earned by a card is seen.

## Fades and slides.
const FADE_IN := 0.2
const FADE_OUT := 0.24
const SLIDE := 18.0
## Time on screen at full strength, before the fades.
const HOLD_SYNERGY := 2.3
const HOLD_BOSS := 2.1
const HOLD_NOTICE := 1.5
## The shortest a banner stays once others are waiting.
const HOLD_RUSHED := 1.1
## Announcements older than this when their turn comes are skipped.
const STALE_AFTER := 2.5
const MAX_WIDTH := 640.0
const TITLE_SIZE := 30
const TITLE_MIN_SIZE := 20

## Called with no arguments; true while banners should wait.
var holds := Callable()
## Every notice that has reached the screen, for tests and tools.
var shown: Array[Dictionary] = []

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _age := 0.0
var _hold := 0.0
var _clock := 0.0
var _panel: PanelContainer
var _kicker: Label
var _title: Label
var _body: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var column := UiKit.vbox(2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UiKit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kicker = UiKit.caption("", UiTheme.TINY, Palette.GOLD)
	head.add_child(_kicker)
	_title = UiKit.title("", TITLE_SIZE, Palette.GOLD)
	head.add_child(_title)
	column.add_child(head)
	_body = UiKit.paragraph("", UiTheme.TINY + 1, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_body)
	var pad := UiKit.margin(column, 18, 6, 18, 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pad)


## Queues a notice. `style` is synergy, boss, warning, elite, good, title or info.
func notify(title_text: String, body_text: String = "", style: String = "info") -> void:
	if title_text.is_empty():
		return
	if str(_current.get("title", "")) == title_text:
		return
	for waiting in _queue:
		if str(waiting.title) == title_text:
			return
	var notice := {"title": title_text, "body": body_text, "style": style, "born": _clock}
	if style == "boss":
		_queue.push_front(notice)
	else:
		_queue.append(notice)


func notify_synergy(synergy_name: String, desc: String) -> void:
	notify(synergy_name, desc, "synergy")


## True while a banner is on screen.
func is_showing() -> bool:
	return not _current.is_empty()


func current_title() -> String:
	return str(_current.get("title", ""))


func waiting() -> int:
	return _queue.size()


## The on-screen rectangle of the banner, for tests and tools.
func banner_rect() -> Rect2:
	return _panel.get_global_rect()


func _process(delta: float) -> void:
	advance(delta)


## One tick of the queue. Public so tests can drive it exactly.
func advance(delta: float) -> void:
	_clock += delta
	if _current.is_empty():
		if not _held():
			_next()
		return
	# Behind an upgrade screen or the pause menu: hide, and carry on afterwards.
	_panel.visible = not _held()
	if not _panel.visible:
		return
	_age += delta
	# With others waiting, shorten the hold - but always leave time to read it.
	var hold := _hold if _queue.is_empty() else minf(_hold, HOLD_RUSHED)
	var fade_end := FADE_IN + hold + FADE_OUT
	if _age >= fade_end:
		_finish()
		return
	_pose(_age, hold)


func _held() -> bool:
	return holds.is_valid() and bool(holds.call())


func _next() -> void:
	while not _queue.is_empty():
		var notice: Dictionary = _queue.pop_front()
		var fresh: bool = _clock - float(notice.born) <= STALE_AFTER
		if notice.style == "synergy" or notice.style == "boss" or fresh:
			_begin(notice)
			return


func _begin(notice: Dictionary) -> void:
	_current = notice
	shown.append(notice)
	_age = 0.0
	var color := Palette.CYAN
	_hold = HOLD_NOTICE
	match str(notice.style):
		"synergy":
			color = Palette.GOLD
			_hold = HOLD_SYNERGY
		"boss":
			color = Palette.RED
			_hold = HOLD_BOSS
		"warning":
			color = Palette.AMBER
		"elite":
			color = Palette.GOLD
		"good":
			color = Palette.GREEN
		"title":
			color = Palette.TEXT
	_panel.add_theme_stylebox_override("panel", UiTheme.box(Palette.with_alpha(Palette.PANEL_SOLID, 0.86), color, 14, 2, 12.0))
	_kicker.text = "SYNERGY" if notice.style == "synergy" else ""
	_kicker.visible = not _kicker.text.is_empty()
	_kicker.add_theme_color_override("font_color", color)
	_title.text = str(notice.title)
	_title.add_theme_color_override("font_color", color)
	_title.add_theme_font_size_override("font_size", _fitted_size(str(notice.title)))
	_body.text = str(notice.body)
	_body.visible = not _body.text.is_empty()
	_panel.visible = true
	_lay_out()
	_pose(0.0, _hold)


## The largest title size that fits the banner on one line.
func _fitted_size(text: String) -> int:
	var room := _width() - 44.0 - (_kicker.get_minimum_size().x + 10.0 if _kicker.visible else 0.0)
	var font := UiTheme.font_title()
	var font_size := TITLE_SIZE
	while font_size > TITLE_MIN_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > room:
		font_size -= 2
	return font_size


func _width() -> float:
	var available := size.x if size.x > 0.0 else get_viewport_rect().size.x - 24.0
	return minf(available, MAX_WIDTH)


func _lay_out() -> void:
	var width := _width()
	# A wrapping label is as tall as its width allows: give it the width first.
	_body.custom_minimum_size = Vector2(width - 36.0, 0.0)
	_panel.custom_minimum_size = Vector2(width, 0.0)
	_panel.size = Vector2(width, 0.0)
	_panel.position.x = (size.x - width) * 0.5


## Slide and fade for a banner `age` seconds in.
func _pose(age: float, hold: float) -> void:
	var into := clampf(age / FADE_IN, 0.0, 1.0)
	var out := clampf((age - FADE_IN - hold) / FADE_OUT, 0.0, 1.0)
	var eased := 1.0 - (1.0 - into) * (1.0 - into)
	_panel.size.y = 0.0
	_panel.modulate.a = eased * (1.0 - out)
	_panel.position.y = -SLIDE * (1.0 - eased) - SLIDE * 0.5 * out
	if size.x > 0.0:
		_panel.position.x = (size.x - _panel.size.x) * 0.5


func _finish() -> void:
	_current = {}
	_panel.visible = false
	if not _held():
		_next()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_showing() and is_node_ready():
		_lay_out()
