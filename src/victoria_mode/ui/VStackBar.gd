class_name VStackBar
extends Control
## Barra apilada horizontal (composición de POPs, culturas, ideologías...).
## segments: Array de [valor, Color, etiqueta]

var segments: Array = []


static func create(h: float = 14.0) -> VStackBar:
	var b := VStackBar.new()
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b


func set_segments(segs: Array) -> void:
	segments = segs
	var total := 0.0
	for s in segs:
		total += float(s[0])
	var lines := []
	for s in segs:
		if total > 0.0 and float(s[0]) > 0.0:
			lines.append("%s: %.1f%%" % [s[2], float(s[0]) / total * 100.0])
	tooltip_text = "\n".join(lines)
	queue_redraw()


func _draw() -> void:
	var total := 0.0
	for s in segments:
		total += float(s[0])
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL_INSET)
	if total > 0.0:
		var x := 0.0
		for s in segments:
			var w := float(s[0]) / total * size.x
			draw_rect(Rect2(x, 0, w, size.y), s[1])
			x += w
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.GOLD_DIM, false, 1.0)
