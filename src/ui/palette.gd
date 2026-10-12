class_name Palette
extends RefCounted
## The game's colours. UI code refers to these names, never to raw hex values,
## so a re-skin is a change to this one file.

const BG := Color("05070d")
const PANEL := Color(0.043, 0.071, 0.125, 0.86)
const PANEL_SOLID := Color("0b1220")
const PANEL_RAISED := Color(0.075, 0.118, 0.2, 0.92)
const LINE := Color("1d3350")
const SCRIM := Color(0.008, 0.012, 0.027, 0.78)

const CYAN := Color("2de2ff")
const MAGENTA := Color("ff3d9a")
const AMBER := Color("ffc247")
const GREEN := Color("5cffb1")
const RED := Color("ff4d5e")
const VIOLET := Color("b58cff")
const GOLD := Color("ffd15c")

const TEXT := Color("eaf6ff")
const MUTED := Color("7c8da6")
const DIM := Color("46566e")

const CREDITS := GOLD
const CRYSTALS := VIOLET
const HEALTH := Color("ff5470")
const ENERGY := GREEN


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


static func currency(id: String) -> Color:
	return CRYSTALS if id == Economy.CRYSTALS else CREDITS
