class_name LicencesModal
extends Modal
## Third-party notices, opened from Settings. Godot's MIT licence asks for its
## notice to ship with the game, and so do most of the components compiled into
## the engine (FreeType, HarfBuzz, Mbed TLS, the Open Sans font and others).
## Those come straight from the engine binary, so the list stays correct when
## the engine is updated; the native AdMob bridge's pieces come from
## `third_party` in game.json and are listed only when the bridge is present.

## Engine notices run to about 85,000 characters; text is added in blocks of
## this size so no single label gets enormous.
const BLOCK_CHARS := 6000


func _init() -> void:
	heading = "LICENCES"
	accent = Palette.CYAN


func _build(into: VBoxContainer) -> void:
	var list := UiKit.vbox(14)
	var scroller := UiKit.scroll(list)
	scroller.custom_minimum_size = Vector2(0, maxf(get_viewport_rect().size.y * 0.62, 480.0))
	into.add_child(scroller)

	list.add_child(UiKit.paragraph("%s is made with the Godot Engine and the software below. Full licence texts follow the list." % App.data.title(), UiTheme.SMALL, Palette.TEXT))

	_section(list, "GODOT ENGINE")
	_text(list, reflow(Engine.get_license_text()))

	var extras := third_party_entries()
	if not extras.is_empty():
		_section(list, "ADS")
		for entry: Dictionary in extras:
			list.add_child(UiKit.label(GameData.text(entry, "name"), UiTheme.SMALL, Palette.TEXT))
			var lines := PackedStringArray([GameData.text(entry, "copyright")])
			if entry.has("licence"):
				lines.append("Licence: %s (full text below)" % GameData.text(entry, "licence"))
			if entry.has("terms"):
				lines.append(GameData.text(entry, "terms"))
			_text(list, "\n".join(lines))

	_section(list, "ENGINE COMPONENTS")
	for component: Dictionary in Engine.get_copyright_info():
		if str(component.get("name", "")) == "Godot Engine":
			continue
		list.add_child(UiKit.label(str(component.get("name", "")), UiTheme.SMALL, Palette.TEXT))
		var lines := PackedStringArray()
		for part: Dictionary in component.get("parts", []):
			for holder: String in part.get("copyright", []):
				lines.append("Copyright (c) " + holder)
			lines.append("Licence: " + str(part.get("license", "")))
		_text(list, "\n".join(lines))

	_section(list, "LICENCE TEXTS")
	var texts: Dictionary = Engine.get_license_info()
	for licence_name: String in texts:
		list.add_child(UiKit.label(licence_name, UiTheme.SMALL, Palette.TEXT))
		_text(list, reflow(str(texts[licence_name])))


## The game.json `third_party` entries for what this build contains: godot-cpp
## whenever the AdMob bridge is loaded, Google's SDKs only where it is real.
static func third_party_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Engine.has_singleton("AdMob"):
		return out
	var real_sdk: bool = Engine.get_singleton("AdMob").is_supported()
	for entry: Dictionary in GameData.list(App.data.game, "third_party"):
		var where := GameData.text(entry, "in")
		if where == "admob_bridge" or (where == "admob_sdk" and real_sdk):
			out.append(entry)
	return out


## Licence texts are hard-wrapped at about 80 columns, which wraps raggedly on a
## phone. Joins the lines of each paragraph; blank lines still separate them.
static func reflow(body: String) -> String:
	var paragraphs := PackedStringArray()
	for paragraph: String in body.replace("\r", "").split("\n\n"):
		var lines := PackedStringArray()
		for line: String in paragraph.split("\n"):
			lines.append(line.strip_edges())
		paragraphs.append(" ".join(lines).strip_edges())
	return "\n\n".join(paragraphs)


func _section(list: VBoxContainer, title_text: String) -> void:
	list.add_child(UiKit.gap(6))
	list.add_child(UiKit.caption(title_text, UiTheme.TINY, accent))
	list.add_child(UiKit.divider(accent))


func _text(list: VBoxContainer, body: String) -> void:
	var at := 0
	while at < body.length():
		var end := mini(at + BLOCK_CHARS, body.length())
		if end < body.length():
			var paragraph_break := body.rfind("\n", end)
			if paragraph_break > at:
				end = paragraph_break + 1
		list.add_child(UiKit.paragraph(body.substr(at, end - at).strip_edges(), UiTheme.TINY, Palette.MUTED))
		at = end
