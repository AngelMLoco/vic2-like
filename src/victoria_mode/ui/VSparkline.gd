class_name VSparkline
extends Control
## Minigráfica de una serie (historial de precios). La línea discontinua marca la referencia (precio base).

var values: Array = []
var reference: float = 0.0


static func create(vals: Array, ref: float, size_px: Vector2 = Vector2(90, 18)) -> VSparkline:
	var s := VSparkline.new()
	s.values = vals
	s.reference = ref
	s.custom_minimum_size = size_px
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	if not vals.is_empty():
		s.tooltip_text = "Últimos %d meses: %.2f → %.2f (base %.2f)" % [vals.size(), float(vals[0]), float(vals[-1]), ref]
	return s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL_INSET)
	if values.size() < 2:
		return
	var lo := reference
	var hi := reference
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span := maxf(hi - lo, 0.0001)
	var pts := PackedVector2Array()
	for i in values.size():
		var x := float(i) / float(values.size() - 1) * (size.x - 2.0) + 1.0
		var y := size.y - 1.0 - (float(values[i]) - lo) / span * (size.y - 2.0)
		pts.append(Vector2(x, y))
	var ry := size.y - 1.0 - (reference - lo) / span * (size.y - 2.0)
	draw_dashed_line(Vector2(0, ry), Vector2(size.x, ry), UiTheme.TEXT_MUTED, 1.0, 3.0)
	var col := UiTheme.POSITIVE if float(values[-1]) >= float(values[0]) else UiTheme.NEGATIVE
	draw_polyline(pts, col, 1.5, true)
