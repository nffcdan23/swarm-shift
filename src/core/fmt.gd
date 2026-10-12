class_name Fmt
extends RefCounted
## Small display-formatting helpers shared by UI and logs.


static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out


## 950 -> "950", 12_340 -> "12.3K", 4_560_000 -> "4.56M".
static func compact(n: float) -> String:
	var a := absf(n)
	if a < 10000.0:
		return commas(int(round(n)))
	if a < 1000000.0:
		return "%.1fK" % (n / 1000.0)
	if a < 1000000000.0:
		return "%.2fM" % (n / 1000000.0)
	return "%.2fB" % (n / 1000000000.0)


static func time_mmss(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	@warning_ignore("integer_division")
	var m := total / 60
	return "%d:%02d" % [m, total % 60]


static func percent(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


static func hex(code: String, fallback: Color = Color.WHITE) -> Color:
	if code.is_empty() or not Color.html_is_valid(code):
		return fallback
	return Color.html(code)


static func round_to(value: float, step: int) -> int:
	return int(round(value / float(step))) * step
