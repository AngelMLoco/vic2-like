class_name VIcon
extends Control
## Iconos vectoriales simples dibujados por código (originales, sin assets externos).

var icon: String = ""
var color: Color = UiTheme.ACCENT


static func create(icon_id: String, px: float = 20.0, col: Color = UiTheme.ACCENT) -> VIcon:
	var i := VIcon.new()
	i.icon = icon_id
	i.color = col
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s: float = min(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := color
	var dark := Color(0, 0, 0, 0.6)
	var w: float = max(1.5, s * 0.09)
	match icon:
		"production":  # engranaje
			var ctr := o + Vector2(s, s) * 0.5
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(ctr + Vector2(cos(a), sin(a)) * s * 0.28, ctr + Vector2(cos(a), sin(a)) * s * 0.46, c, s * 0.14)
			draw_circle(ctr, s * 0.32, c)
			draw_circle(ctr, s * 0.13, dark)
		"budget":  # moneda
			var ctr2 := o + Vector2(s, s) * 0.5
			draw_circle(ctr2, s * 0.42, c)
			draw_arc(ctr2, s * 0.32, 0, TAU, 24, dark, w * 0.7)
			draw_line(ctr2 + Vector2(0, -s * 0.18), ctr2 + Vector2(0, s * 0.18), dark, w)
		"technology":  # matraz
			var pts := PackedVector2Array([o + Vector2(s * 0.38, s * 0.1), o + Vector2(s * 0.62, s * 0.1), o + Vector2(s * 0.62, s * 0.4),
				o + Vector2(s * 0.88, s * 0.88), o + Vector2(s * 0.12, s * 0.88), o + Vector2(s * 0.38, s * 0.4)])
			draw_colored_polygon(pts, c)
			draw_rect(Rect2(o + Vector2(s * 0.24, s * 0.62), Vector2(s * 0.52, s * 0.08)), dark)
		"politics":  # columna/balanza
			draw_rect(Rect2(o + Vector2(s * 0.15, s * 0.12), Vector2(s * 0.7, s * 0.12)), c)
			for i in 3:
				draw_rect(Rect2(o + Vector2(s * (0.22 + i * 0.22), s * 0.28), Vector2(s * 0.12, s * 0.46)), c)
			draw_rect(Rect2(o + Vector2(s * 0.1, s * 0.78), Vector2(s * 0.8, s * 0.12)), c)
		"population":  # personas
			draw_circle(o + Vector2(s * 0.35, s * 0.3), s * 0.14, c)
			draw_circle(o + Vector2(s * 0.68, s * 0.34), s * 0.12, c.darkened(0.15))
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.12, s * 0.9), o + Vector2(s * 0.2, s * 0.5), o + Vector2(s * 0.5, s * 0.5), o + Vector2(s * 0.58, s * 0.9)]), c)
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.5, s * 0.9), o + Vector2(s * 0.56, s * 0.54), o + Vector2(s * 0.8, s * 0.54), o + Vector2(s * 0.9, s * 0.9)]), c.darkened(0.15))
		"trade":  # fardo/caja
			draw_rect(Rect2(o + Vector2(s * 0.12, s * 0.3), Vector2(s * 0.76, s * 0.56)), c)
			draw_line(o + Vector2(s * 0.12, s * 0.48), o + Vector2(s * 0.88, s * 0.48), dark, w)
			draw_line(o + Vector2(s * 0.5, s * 0.3), o + Vector2(s * 0.5, s * 0.86), dark, w)
			draw_line(o + Vector2(s * 0.3, s * 0.3), o + Vector2(s * 0.45, s * 0.12), c, w)
			draw_line(o + Vector2(s * 0.7, s * 0.3), o + Vector2(s * 0.55, s * 0.12), c, w)
		"diplomacy":  # pergamino con sello
			draw_rect(Rect2(o + Vector2(s * 0.18, s * 0.12), Vector2(s * 0.64, s * 0.72)), c)
			for i in 3:
				draw_line(o + Vector2(s * 0.28, s * (0.28 + i * 0.14)), o + Vector2(s * 0.72, s * (0.28 + i * 0.14)), dark, w * 0.6)
			draw_circle(o + Vector2(s * 0.64, s * 0.78), s * 0.14, Color("b8323a"))
		"military":  # espadas cruzadas
			draw_line(o + Vector2(s * 0.15, s * 0.15), o + Vector2(s * 0.85, s * 0.85), c, w * 1.3)
			draw_line(o + Vector2(s * 0.85, s * 0.15), o + Vector2(s * 0.15, s * 0.85), c, w * 1.3)
			draw_line(o + Vector2(s * 0.62, s * 0.78), o + Vector2(s * 0.78, s * 0.62), c, w * 1.6)
			draw_line(o + Vector2(s * 0.22, s * 0.62), o + Vector2(s * 0.38, s * 0.78), c, w * 1.6)
		"prestige":  # estrella
			var ctr3 := o + Vector2(s, s) * 0.5
			var pts2 := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				pts2.append(ctr3 + Vector2(cos(a), sin(a)) * (s * 0.46 if i % 2 == 0 else s * 0.2))
			draw_colored_polygon(pts2, c)
		"literacy":  # libro
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.08, s * 0.2), o + Vector2(s * 0.48, s * 0.28), o + Vector2(s * 0.48, s * 0.88), o + Vector2(s * 0.08, s * 0.8)]), c)
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.52, s * 0.28), o + Vector2(s * 0.92, s * 0.2), o + Vector2(s * 0.92, s * 0.8), o + Vector2(s * 0.52, s * 0.88)]), c.darkened(0.15))
		"infamy":  # calavera simplificada
			draw_circle(o + Vector2(s * 0.5, s * 0.42), s * 0.32, c)
			draw_rect(Rect2(o + Vector2(s * 0.34, s * 0.62), Vector2(s * 0.32, s * 0.24)), c)
			draw_circle(o + Vector2(s * 0.38, s * 0.42), s * 0.08, dark)
			draw_circle(o + Vector2(s * 0.62, s * 0.42), s * 0.08, dark)
		"exhaustion":  # gota
			draw_circle(o + Vector2(s * 0.5, s * 0.62), s * 0.26, c)
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.5, s * 0.08), o + Vector2(s * 0.74, s * 0.55), o + Vector2(s * 0.26, s * 0.55)]), c)
		"alert":  # campana
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.5, s * 0.1), o + Vector2(s * 0.78, s * 0.35), o + Vector2(s * 0.84, s * 0.74), o + Vector2(s * 0.16, s * 0.74), o + Vector2(s * 0.22, s * 0.35)]), c)
			draw_circle(o + Vector2(s * 0.5, s * 0.84), s * 0.1, c)
		"pause":
			draw_rect(Rect2(o + Vector2(s * 0.22, s * 0.18), Vector2(s * 0.2, s * 0.64)), c)
			draw_rect(Rect2(o + Vector2(s * 0.58, s * 0.18), Vector2(s * 0.2, s * 0.64)), c)
		"play":
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.25, s * 0.15), o + Vector2(s * 0.82, s * 0.5), o + Vector2(s * 0.25, s * 0.85)]), c)
		_:
			draw_circle(o + Vector2(s, s) * 0.5, s * 0.35, c)
