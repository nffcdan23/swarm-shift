class_name ShopScreen
extends MenuScreen
## The store. Laid out so the honest facts are obvious: what each thing is,
## what it costs, and that none of it is needed to play. No timers, no
## countdowns, no "only 2 left" - and a free option at the top of the list.

var _list: VBoxContainer
var _busy := false


func _build() -> void:
	var column := UiKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	column.add_child(header("Shop", "Everything here is optional. The whole game can be played for free."))
	_list = UiKit.vbox(10)
	column.add_child(UiKit.scroll(_list))


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	_list.add_child(_section("FREE"))
	_list.add_child(_ad_card())

	_list.add_child(_section("PACKS"))
	for product in App.store.catalog():
		_list.add_child(_product_card(product))

	_list.add_child(_section("EXCHANGE"))
	for offer: Dictionary in GameData.list(App.data.monetization, "exchange"):
		_list.add_child(_exchange_card(offer))

	var restore := NeonButton.make("RESTORE PURCHASES", NeonButton.Kind.GHOST, Palette.MUTED, "restore", 64.0, UiTheme.SMALL)
	restore.pressed.connect(_restore)
	_list.add_child(restore)
	if App.store.provider is MockStoreProvider:
		_list.add_child(UiKit.paragraph("Development build: purchases and ads are simulated and no payment is taken.", UiTheme.TINY, Palette.DIM.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER))
	_list.add_child(UiKit.gap(8))


func _section(text: String) -> Label:
	return UiKit.caption(text, UiTheme.TINY, Palette.MUTED)


func _row_card(accent: Color, icon_id: String, icon_color: Color, title_text: String, body_text: String, action: Control, tag_text: String = "") -> PanelContainer:
	var card := UiKit.card(accent, 16, 8)
	var row := UiKit.hbox(14)
	row.add_child(IconGlyph.make(icon_id, 54.0, icon_color, true))
	var text := UiKit.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiKit.hbox(10)
	head.add_child(UiKit.label(title_text, UiTheme.BODY, Palette.TEXT))
	if not tag_text.is_empty():
		head.add_child(UiKit.tag(tag_text, Palette.GOLD))
	text.add_child(head)
	text.add_child(UiKit.paragraph(body_text, UiTheme.TINY + 1, Palette.MUTED))
	row.add_child(text)
	if action != null:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(action)
	UiKit.card_body(card).add_child(row)
	return card


func _ad_card() -> PanelContainer:
	var left := App.ads.shop_credit_ads_left()
	var amount := App.ads.shop_credit_reward()
	var action: Control
	if left > 0 and App.ads.rewarded_available(AdsService.SHOP_CREDITS):
		var watch := NeonButton.make("WATCH", NeonButton.Kind.PRIMARY, Palette.GREEN, "ad", 64.0, UiTheme.SMALL)
		watch.min_width = 150.0
		watch.click_sound = ""
		watch.pressed.connect(_watch_ad)
		action = watch
	else:
		action = UiKit.tag("BACK TOMORROW", Palette.MUTED)
	return _row_card(Palette.GREEN, "credit", Palette.CREDITS, "%d Credits" % amount,
		"Watch a short ad. %d left today." % left, action)


func _product_card(product: Dictionary) -> PanelContainer:
	var id := str(product.id)
	var owned := bool(product.owned)
	var action: Control
	if owned:
		action = UiKit.tag("OWNED", Palette.GREEN, UiTheme.SMALL)
	else:
		var buy := NeonButton.make(str(product.price), NeonButton.Kind.PRIMARY, Palette.CYAN, "", 64.0, UiTheme.SMALL)
		buy.min_width = 150.0
		buy.click_sound = ""
		buy.pressed.connect(_buy.bind(id))
		action = buy
	var icon_id := str(product.icon)
	var icon_color := Palette.CRYSTALS if icon_id == "crystal" else Palette.GOLD
	return _row_card(Palette.GOLD if id == "starter_pack" and not owned else Palette.LINE.lightened(0.3), icon_id, icon_color,
		str(product.name), str(product.desc), action, str(product.tag))


func _exchange_card(offer: Dictionary) -> PanelContainer:
	var price := GameData.integer(offer, "crystals")
	var gain := GameData.integer(offer, "credits")
	var affordable := App.economy.can_afford(Economy.CRYSTALS, price)
	var swap := NeonButton.make(str(price), NeonButton.Kind.PRIMARY if affordable else NeonButton.Kind.SECONDARY,
		Palette.CRYSTALS if affordable else Palette.MUTED, "crystal", 64.0, UiTheme.SMALL)
	swap.min_width = 150.0
	swap.click_sound = ""
	swap.pressed.connect(_exchange.bind(price, gain))
	return _row_card(Palette.LINE.lightened(0.3), "credit", Palette.CREDITS, "%s Credits" % Fmt.commas(gain),
		"Trade Crystals for Credits.", swap)


func _watch_ad() -> void:
	if _busy:
		return
	_busy = true
	var granted: int = await App.ads.claim_shop_credits()
	_busy = false
	if granted > 0:
		App.audio.play("ui_claim")
		App.haptics.success()
		shell.toast("+%d Credits" % granted, Palette.CREDITS, "credit")
	refresh()


func _buy(product_id: String) -> void:
	if _busy:
		return
	_busy = true
	var ok: bool = await App.store.purchase(product_id)
	_busy = false
	if ok:
		App.audio.play("ui_purchase")
		App.haptics.success()
		shell.toast("Purchase complete - thank you!", Palette.GREEN, "check")
	refresh()
	shell.refresh_badges()


func _exchange(price: int, gain: int) -> void:
	if not App.economy.spend(Economy.CRYSTALS, price, "exchange"):
		shell.deny(Economy.CRYSTALS)
		return
	App.economy.grant(Economy.CREDITS, gain, "exchange")
	App.audio.play("ui_purchase")
	App.haptics.success()
	refresh()
	shell.refresh_badges()


func _restore() -> void:
	if _busy:
		return
	_busy = true
	var restored: int = await App.store.restore()
	_busy = false
	shell.toast("%d purchase%s restored" % [restored, "" if restored == 1 else "s"] if restored > 0 else "Nothing to restore", Palette.CYAN, "restore")
	refresh()
