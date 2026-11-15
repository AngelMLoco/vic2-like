class_name VFlagView
extends Control
## Bandera placeholder original, dibujada a partir de un patrón definido en datos:
## countries.json → "flag": {"pattern": "...", "colors": ["rrggbb", ...]}.

var pattern: String = "tricolor_v"
var colors: Array = [Color.GRAY, Color.WHITE, Color.BLACK]


static func create(flag: Dictionary, size: Vector2) -> VFlagView:
	var f := VFlagView.new()
	f.custom_minimum_size = size
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.set_flag(flag)
	return f


func set_flag(flag: Dictionary) -> void:
	pattern = flag.get("pattern", "tricolor_v")
	colors = []
	for c in flag.get("colors", ["888888", "dddddd", "333333"]):
		colors.append(Color(c) if c is String else c)
	while colors.size() < 3:
		colors.append(Color.WHITE)
	queue_redraw()


func clear_flag() -> void:
	pattern = "none"
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var a: Color = colors[0]
	var b: Color = colors[1]
	var c: Color = colors[2]
	match pattern:
		"none":
			draw_rect(Rect2(0, 0, w, h), Color("3a3528"))
			draw_line(Vector2(0, 0), Vector2(w, h), Color("5a5240"), 1.0)
			draw_line(Vector2(w, 0), Vector2(0, h), Color("5a5240"), 1.0)
		"tricolor_v":
			draw_rect(Rect2(0, 0, w / 3.0, h), a)
			draw_rect(Rect2(w / 3.0, 0, w / 3.0, h), b)
			draw_rect(Rect2(2.0 * w / 3.0, 0, w / 3.0 + 0.5, h), c)
		"tricolor_h":
			draw_rect(Rect2(0, 0, w, h / 3.0), a)
			draw_rect(Rect2(0, h / 3.0, w, h / 3.0), b)
			draw_rect(Rect2(0, 2.0 * h / 3.0, w, h / 3.0 + 0.5), c)
		"bicolor_h":
			draw_rect(Rect2(0, 0, w, h / 2.0), a)
			draw_rect(Rect2(0, h / 2.0, w, h / 2.0), b)
		"bicolor_v":
			draw_rect(Rect2(0, 0, w / 2.0, h), a)
			draw_rect(Rect2(w / 2.0, 0, w / 2.0, h), b)
		"nordic_cross":
			draw_rect(Rect2(0, 0, w, h), a)
			var t := h * 0.22
			draw_rect(Rect2(w * 0.3, 0, t, h), b)
			draw_rect(Rect2(0, h * 0.5 - t * 0.5, w, t), b)
			draw_rect(Rect2(w * 0.3 + t * 0.25, 0, t * 0.5, h), c)
			draw_rect(Rect2(0, h * 0.5 - t * 0.25, w, t * 0.5), c)
		"cross":
			draw_rect(Rect2(0, 0, w, h), a)
			var t2 := h * 0.24
			draw_rect(Rect2(w * 0.5 - t2 * 0.5, 0, t2, h), b)
			draw_rect(Rect2(0, h * 0.5 - t2 * 0.5, w, t2), b)
		"saltire":
			draw_rect(Rect2(0, 0, w, h), a)
			draw_line(Vector2(0, 0), Vector2(w, h), b, h * 0.18)
			draw_line(Vector2(w, 0), Vector2(0, h), b, h * 0.18)
		"canton":
			draw_rect(Rect2(0, 0, w, h), a)
			for i in 3:
				draw_rect(Rect2(0, h * (0.2 + i * 0.3), w, h * 0.12), c)
			draw_rect(Rect2(0, 0, w * 0.45, h * 0.55), b)
			draw_circle(Vector2(w * 0.225, h * 0.275), h * 0.12, a)
		"disc":
			draw_rect(Rect2(0, 0, w, h), b)
			draw_circle(Vector2(w * 0.5, h * 0.5), h * 0.3, a)
			draw_arc(Vector2(w * 0.5, h * 0.5), h * 0.3, 0, TAU, 32, c, max(1.0, h * 0.05))
		"diagonal":
			draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(0, h)]), a)
			draw_colored_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), b)
			draw_line(Vector2(w, 0), Vector2(0, h), c, h * 0.12)
		"border":
			draw_rect(Rect2(0, 0, w, h), b)
			draw_rect(Rect2(w * 0.12, h * 0.16, w * 0.76, h * 0.68), a)
			draw_circle(Vector2(w * 0.5, h * 0.5), h * 0.14, c)
		"chevron":
			draw_rect(Rect2(0, 0, w, h / 2.0), a)
			draw_rect(Rect2(0, h / 2.0, w, h / 2.0), b)
			draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.42, h * 0.5), Vector2(0, h)]), c)
		_:
			draw_rect(Rect2(0, 0, w, h), a)
	# marco y brillo sutil
	draw_rect(Rect2(0, 0, w, h * 0.45), Color(1, 1, 1, 0.07))
	draw_rect(Rect2(0, 0, w, h), Color(0.0, 0.0, 0.0, 0.85), false, 1.0)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color(0.79, 0.64, 0.36, 0.55), false, 1.0)
