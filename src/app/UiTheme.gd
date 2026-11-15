class_name UiTheme
extends RefCounted
## Tema visual compartido: "Victoria II modernizada".
## Paneles oscuros de tono pergamino/bronce, cabeceras verde oscuro, bordes dorados,
## tipografía clara y márgenes generosos. Todo generado por código (sin assets externos).

const BG := Color("17150f")
const PANEL := Color("221f17")
const PANEL_LIGHT := Color("2d2a20")
const PANEL_INSET := Color("15130e")
const HEADER := Color("233328")
const HEADER_DARK := Color("18241c")
const GOLD := Color("c9a45c")
const GOLD_DIM := Color("7d6537")
const TEXT := Color("ece3cf")
const TEXT_DIM := Color("b3a78d")
const TEXT_MUTED := Color("7f7562")
const POSITIVE := Color("8fd17a")
const NEGATIVE := Color("e0705a")
const ACCENT := Color("e8c66f")
const BUTTON := Color("3a3326")
const BUTTON_HOVER := Color("4b4231")
const BUTTON_PRESSED := Color("2a2419")
const SELECTED := Color("5c4a24")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 3, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = max(2, margin - 2)
	sb.content_margin_bottom = max(2, margin - 2)
	sb.anti_aliasing = true
	return sb


static func panel_box() -> StyleBoxFlat:
	var sb := box(PANEL, GOLD_DIM, 1, 4, 10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	return sb


static func header_box() -> StyleBoxFlat:
	var sb := box(HEADER, GOLD_DIM, 1, 3, 10)
	sb.border_width_bottom = 2
	sb.border_color = GOLD
	return sb


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_MUTED)
	t.set_stylebox("normal", "Button", box(BUTTON, GOLD_DIM, 1, 3, 10))
	t.set_stylebox("hover", "Button", box(BUTTON_HOVER, GOLD, 1, 3, 10))
	t.set_stylebox("pressed", "Button", box(BUTTON_PRESSED, ACCENT, 1, 3, 10))
	t.set_stylebox("disabled", "Button", box(Color("2a261d"), Color("4a4130"), 1, 3, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())

	t.set_stylebox("normal", "LineEdit", box(PANEL_INSET, GOLD_DIM, 1, 3, 8))
	t.set_stylebox("focus", "LineEdit", box(PANEL_INSET, GOLD, 1, 3, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)

	t.set_stylebox("panel", "TooltipPanel", box(Color("1b1912"), GOLD, 1, 3, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

	t.set_stylebox("panel", "ItemList", box(PANEL_INSET, GOLD_DIM, 1, 3, 4))
	t.set_stylebox("selected", "ItemList", box(SELECTED, GOLD, 1, 2, 4))
	t.set_stylebox("selected_focus", "ItemList", box(SELECTED, GOLD, 1, 2, 4))
	t.set_stylebox("hovered", "ItemList", box(Color("2f2a1e"), Color(0, 0, 0, 0), 0, 2, 4))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", ACCENT)

	t.set_stylebox("panel", "TabContainer", box(PANEL, GOLD_DIM, 1, 3, 10))
	t.set_stylebox("tab_selected", "TabContainer", box(HEADER, GOLD, 1, 3, 12))
	t.set_stylebox("tab_unselected", "TabContainer", box(BUTTON, GOLD_DIM, 1, 3, 12))
	t.set_stylebox("tab_hovered", "TabContainer", box(BUTTON_HOVER, GOLD, 1, 3, 12))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)

	var grabber := box(GOLD, Color(0, 0, 0, 0), 0, 4, 0)
	t.set_stylebox("slider", "HSlider", box(PANEL_INSET, GOLD_DIM, 1, 3, 3))
	t.set_stylebox("grabber_area", "HSlider", box(GOLD_DIM, Color(0, 0, 0, 0), 0, 3, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, Color(0, 0, 0, 0), 0, 3, 3))
	t.set_stylebox("scroll", "VScrollBar", box(PANEL_INSET, Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(ACCENT, Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, Color(0, 0, 0, 0), 0, 4, 0))

	t.set_stylebox("panel", "ProgressBar", box(PANEL_INSET, GOLD_DIM, 1, 2, 0))
	t.set_stylebox("background", "ProgressBar", box(PANEL_INSET, GOLD_DIM, 1, 2, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, Color(0, 0, 0, 0), 0, 2, 0))
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", ACCENT)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

	t.set_stylebox("panel", "PopupMenu", box(PANEL, GOLD, 1, 3, 6))
	t.set_stylebox("normal", "OptionButton", box(BUTTON, GOLD_DIM, 1, 3, 10))
	t.set_stylebox("hover", "OptionButton", box(BUTTON_HOVER, GOLD, 1, 3, 10))
	t.set_stylebox("pressed", "OptionButton", box(BUTTON_PRESSED, ACCENT, 1, 3, 10))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	return t


## Etiqueta con tamaño/color.
static func label(text: String, size: int = 15, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Barra de título de ventana estilo Victoria (cabecera verde con borde dorado).
static func title_bar(text: String, on_close: Callable = Callable()) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", header_box())
	var hb := HBoxContainer.new()
	pc.add_child(hb)
	var l := label(text.to_upper(), 17, ACCENT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	if on_close.is_valid():
		var b := Button.new()
		b.text = "×"
		b.custom_minimum_size = Vector2(30, 26)
		b.tooltip_text = "Cerrar"
		b.pressed.connect(on_close)
		hb.add_child(b)
	return pc


static func button(text: String, cb: Callable = Callable(), min_w: float = 0.0, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func separator() -> ColorRect:
	var c := ColorRect.new()
	c.color = GOLD_DIM
	c.custom_minimum_size = Vector2(1, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func fmt_int(n: float) -> String:
	var v := int(round(n))
	var neg := v < 0
	var s := str(abs(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func fmt_big(n: float) -> String:
	var a: float = abs(n)
	if a >= 1_000_000_000.0:
		return "%.2f mil M" % (n / 1_000_000_000.0)
	if a >= 1_000_000.0:
		return "%.2f M" % (n / 1_000_000.0)
	if a >= 10_000.0:
		return "%.1f k" % (n / 1000.0)
	return fmt_int(n)


static func fmt_money(n: float) -> String:
	return "¤ " + ("%.1f k" % (n / 1000.0) if abs(n) >= 100_000.0 else fmt_int(n))
