class_name VEventPopup
extends PanelContainer
## Ventana de evento del jugador (estilo gran estrategia): ilustración, fecha, título, descripción y opciones
## con tooltip de efectos. Atiende la cola de VEventSystem en orden (no se pierde ningún evento).
## Los acontecimientos mundiales («major», ámbito global) usan un marco especial.
##
## Ilustración: res://assets/events/<art_key>.png si existe; si no, un placeholder original (degradado y
## motivo geométrico con el nombre de la clave), de modo que el arte se puede añadir sin tocar el motor.

signal resolved

var gs: VGameState
var _art: Control
var _art_tex: TextureRect
var _art_label: Label
var _kicker: Label
var _date: Label
var _title: Label
var _desc: RichTextLabel
var _options: VBoxContainer
var _counter: Label
var _frame: StyleBoxFlat


func setup(state: VGameState) -> void:
	gs = state
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -330
	offset_right = 330
	offset_top = -340
	offset_bottom = 340
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = UiTheme.box(UiTheme.PANEL, UiTheme.GOLD_DIM, 2, 4, 12)
	add_theme_stylebox_override("panel", _frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_kicker = UiTheme.label("", 12, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_kicker)
	_art = Panel.new()
	_art.custom_minimum_size = Vector2(0, 230)
	_art.clip_contents = true
	v.add_child(_art)
	_art_tex = TextureRect.new()
	_art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.add_child(_art_tex)
	_art_label = UiTheme.label("", 13, UiTheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_art_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_art_label.position.y -= 26
	_art.add_child(_art_label)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UiTheme.label("", 22, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	_date = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	head.add_child(_date)
	v.add_child(UiTheme.separator())
	_desc = RichTextLabel.new()
	_desc.fit_content = true
	_desc.bbcode_enabled = false
	_desc.custom_minimum_size = Vector2(0, 90)
	_desc.add_theme_color_override("default_color", UiTheme.TEXT)
	_desc.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(_desc)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	v.add_child(_options)
	_counter = UiTheme.label("", 12, UiTheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(_counter)
	visible = false


## Muestra el primer evento de la cola (si hay). Devuelve true si se muestra algo.
func show_next() -> bool:
	var q: Array = VEventSystem.pending(gs)
	if q.is_empty():
		visible = false
		return false
	var item: Dictionary = q[0]
	var e: Dictionary = gs.event_defs.get(item["id"], {})
	if e.is_empty():
		q.remove_at(0)
		return show_next()
	var ctx: Dictionary = item["ctx"]
	var major: bool = e["type"] == "major"
	var world: bool = e["scope"] == "global"
	_kicker.text = "ACONTECIMIENTO MUNDIAL" if world else ("ACONTECIMIENTO" if major else gs.country_name(ctx.get("tag", gs.player_tag)).to_upper())
	_frame.border_color = UiTheme.ACCENT if major else UiTheme.GOLD_DIM
	_frame.set_border_width_all(4 if world else 2)
	_title.text = e["title"]
	_date.text = str(item.get("date", gs.date.text()))
	var desc: String = e["desc"]
	if int(ctx.get("prov", 0)) > 0:
		desc = "%s\n\n(%s)" % [desc, gs.provinces[int(ctx["prov"])]["name"]]
	if String(ctx.get("target", "")) != "":
		desc += "\n\nPaís implicado: %s" % gs.country_name(ctx["target"])
	_desc.text = desc
	_set_art(String(e["art"]), world)
	for ch in _options.get_children():
		ch.queue_free()
	var opts: Array = e["options"]
	for i in opts.size():
		var o: Dictionary = opts[i]
		var ok := VEventSystem.option_available(gs, e, i, ctx)
		var tip := VEventEffects.describe(gs, o["effects"])
		if not o["follow_up"].is_empty():
			tip += "\nLa historia continuará…"
		if not ok:
			tip = "No disponible: " + VEventConditions.explain_fail(gs, o["trigger"], ctx) + "\n" + tip
		var b := UiTheme.button(o["name"], func(): _choose(i), 0.0, tip)
		b.disabled = not ok
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_options.add_child(b)
	_counter.text = ("%d eventos más en espera" % (q.size() - 1)) if q.size() > 1 else ""
	visible = true
	return true


func _choose(i: int) -> void:
	VEventSystem.choose(gs, 0, i)
	resolved.emit()
	if not show_next():
		visible = false


func _set_art(key: String, world: bool) -> void:
	var path := "res://assets/events/%s.png" % key
	if key != "" and ResourceLoader.exists(path):
		_art_tex.texture = load(path)
		_art_label.text = ""
		return
	# placeholder original: degradado según la clave (determinista) y la etiqueta de la ilustración pendiente
	var h := float(absi(key.hash()) % 360) / 360.0
	var top := Color.from_hsv(h, 0.35, 0.32)
	var bottom := Color.from_hsv(fmod(h + 0.08, 1.0), 0.45, 0.12)
	if world:
		top = Color("3a2a5a")
		bottom = Color("0c0a18")
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 64
	gt.height = 64
	_art_tex.texture = gt
	_art_label.text = "[ilustración: %s]" % (key if key != "" else "sin título")
