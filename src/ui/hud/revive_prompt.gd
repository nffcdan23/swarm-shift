class_name RevivePrompt
extends Modal
## Offered once per run after death: watch a rewarded ad to continue. Entirely
## optional, clearly labelled, and it times out to "no" rather than nagging.

signal revive_chosen
signal declined

const WINDOW := 7.0

var _left := WINDOW
var _bar: MeterBar
var _decided := false
var _waiting_for_ad := false


func _init() -> void:
	heading = "CORE DESTROYED"
	accent = Palette.RED
	dismissable = false


func _build(into: VBoxContainer) -> void:
	into.add_child(UiKit.paragraph("Reboot once and keep this run going?", UiTheme.BODY, Palette.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_bar = MeterBar.make(Palette.AMBER, 10.0)
	_bar.set_value(1.0, true)
	into.add_child(_bar)
	into.add_child(UiKit.gap(4))

	var revive := NeonButton.make("REVIVE", NeonButton.Kind.PRIMARY, Palette.GREEN, "ad", 96.0, UiTheme.HEADING)
	revive.pressed.connect(_on_revive)
	into.add_child(revive)
	into.add_child(UiKit.caption("WATCH A SHORT AD  -  50% HEALTH", UiTheme.TINY, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	var give_up := NeonButton.make("NO THANKS", NeonButton.Kind.GHOST, Palette.MUTED, "", 68.0, UiTheme.SMALL)
	give_up.pressed.connect(_decline)
	into.add_child(give_up)


func _process(delta: float) -> void:
	if _decided or _waiting_for_ad:
		return
	_left -= delta
	_bar.set_value(_left / WINDOW)
	if _left <= 0.0:
		_decline()


func _on_revive() -> void:
	if _decided or _waiting_for_ad:
		return
	_waiting_for_ad = true
	var earned: bool = await App.ads.show_rewarded(AdsService.REVIVE)
	_waiting_for_ad = false
	if earned:
		_decided = true
		revive_chosen.emit()
		close()
	else:
		# Ad abandoned or unavailable: leave the choice open a little longer.
		_left = maxf(_left, 3.0)


func _decline() -> void:
	if _decided:
		return
	_decided = true
	declined.emit()
	close()
