class_name VCountrySelect
extends Control
## Selección de nación al estilo Victoria II, modernizada:
## mapamundi interactivo de fondo + ranking lateral + ficha de la nación + botón JUGAR.

signal country_chosen(tag: String)  # selección (clic en lista o mapa)
signal play_pressed(tag: String)
signal back_pressed
signal focus_requested(tag: String)

var gs: VGameState
var selected: String = ""
var _list_box: VBoxContainer
var _search: LineEdit
var _rows := {}
var _detail: VBoxContainer
var _flag: VFlagView
var _name_lbl: Label
var _status_lbl: Label
var _info: RichTextLabel
var _desc: Label
var _play: Button


func setup(state: VGameState) -> void:
	gs = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_list()
	_build_detail()
	refresh_list()
	select("")


func _build_header() -> void:
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UiTheme.header_box())
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -300
	top.offset_right = 340
	top.offset_top = 10
	top.offset_bottom = 70
	add_child(top)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	top.add_child(v)
	v.add_child(UiTheme.label("ELIGE TU NACIÓN", 24, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiTheme.label("1 de enero del año 136 · Escenario de prueba: la Tierra · Haz clic en el mapa o en la lista", 13, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))


func _build_list() -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 10
	panel.offset_right = 450
	panel.offset_top = 10
	panel.offset_bottom = -10
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UiTheme.title_bar("Ranking de naciones"))
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar nación…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): refresh_list())
	v.add_child(_search)
	var head := HBoxContainer.new()
	head.add_child(_col_label("#", 34))
	head.add_child(_col_label("", 34))
	var n := _col_label("Nación", 0)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(n)
	head.add_child(_col_label("Prest.", 46))
	head.add_child(_col_label("Ind.", 40))
	head.add_child(_col_label("Mil.", 40))
	head.add_child(_col_label("Total", 48))
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 1)
	scroll.add_child(_list_box)
	var back := UiTheme.button("« Volver al menú", func(): back_pressed.emit())
	v.add_child(back)


func _col_label(t: String, w: float) -> Label:
	var l := UiTheme.label(t, 12, UiTheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size.x = w
	return l


func _build_detail() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -400
	panel.offset_right = -10
	panel.offset_top = 80
	panel.offset_bottom = -10
	add_child(panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	panel.add_child(_detail)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_detail.add_child(hb)
	_flag = VFlagView.create({}, Vector2(120, 80))
	hb.add_child(_flag)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(nv)
	_name_lbl = UiTheme.label("", 22, UiTheme.ACCENT)
	_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(_name_lbl)
	_status_lbl = UiTheme.label("", 15, UiTheme.TEXT)
	nv.add_child(_status_lbl)
	_detail.add_child(UiTheme.separator())
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.add_theme_font_size_override("normal_font_size", 14)
	_info.add_theme_font_size_override("bold_font_size", 14)
	_detail.add_child(_info)
	_detail.add_child(UiTheme.separator())
	_desc = UiTheme.label("", 14, UiTheme.TEXT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail.add_child(_desc)
	var center_btn := UiTheme.button("Centrar en el mapa", _on_center)
	_detail.add_child(center_btn)
	_play = UiTheme.button("JUGAR", _on_play)
	_play.custom_minimum_size.y = 56
	_play.add_theme_font_size_override("font_size", 24)
	_play.add_theme_stylebox_override("normal", UiTheme.box(Color("3d5a32"), UiTheme.GOLD, 2, 4, 12))
	_play.add_theme_stylebox_override("hover", UiTheme.box(Color("4f7440"), UiTheme.ACCENT, 2, 4, 12))
	_detail.add_child(_play)


func refresh_list() -> void:
	for ch in _list_box.get_children():
		ch.queue_free()
	_rows.clear()
	var filter := _search.text.strip_edges().to_lower() if _search else ""
	var groups := [["great_power", "GRANDES POTENCIAS"], ["secondary_power", "POTENCIAS SECUNDARIAS"],
		["civilized", "NACIONES CIVILIZADAS"], ["uncivilized", "NACIONES NO CIVILIZADAS"]]
	var ranked := VRankingSystem.ranked(gs)
	for g in groups:
		var any := false
		for tag in ranked:
			var c: Dictionary = gs.countries[tag]
			if c["status"] != g[0]:
				continue
			if filter != "" and not c["name"].to_lower().contains(filter) and not tag.to_lower().contains(filter):
				continue
			if not any:
				var h := UiTheme.label(g[1], 12, UiTheme.GOLD)
				h.custom_minimum_size.y = 24
				_list_box.add_child(h)
				any = true
			var row := _make_row(tag)
			_list_box.add_child(row)
			_rows[tag] = row
	_highlight_rows()


func _make_row(tag: String) -> Button:
	var c: Dictionary = gs.countries[tag]
	var b := Button.new()
	b.custom_minimum_size.y = 28
	b.toggle_mode = false
	b.tooltip_text = "%s\n%s · Población %s" % [c["name"], VRankingSystem.status_name(c["status"]), UiTheme.fmt_big(gs.country_population(tag))]
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, 2))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.BUTTON_HOVER, Color(0, 0, 0, 0), 0, 2, 2))
	b.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.SELECTED, UiTheme.GOLD, 1, 2, 2))
	b.pressed.connect(func(): select(tag); country_chosen.emit(tag))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	hb.add_child(_cell(str(c["rank"]), 34, UiTheme.TEXT_DIM))
	var fc := CenterContainer.new()
	fc.custom_minimum_size.x = 34
	fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.add_child(VFlagView.create(c["flag"], Vector2(27, 18)))
	hb.add_child(fc)
	var n := _cell(c["name"], 0, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(n)
	hb.add_child(_cell("%d" % int(c["prestige"]), 46, UiTheme.TEXT_DIM))
	hb.add_child(_cell("%d" % int(c["industry_score"]), 40, UiTheme.TEXT_DIM))
	hb.add_child(_cell("%d" % int(c["military_score"]), 40, UiTheme.TEXT_DIM))
	hb.add_child(_cell("%d" % int(c["total_score"]), 48, UiTheme.ACCENT))
	return b


func _cell(t: String, w: float, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UiTheme.label(t, 13, col, align)
	l.custom_minimum_size.x = w
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _highlight_rows() -> void:
	for tag in _rows:
		var b: Button = _rows[tag]
		if tag == selected:
			b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SELECTED, UiTheme.GOLD, 1, 2, 2))
		else:
			b.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, 2))


func select(tag: String) -> void:
	selected = tag
	_highlight_rows()
	if tag == "" or not gs.countries.has(tag):
		_flag.clear_flag()
		_name_lbl.text = "Ninguna nación seleccionada"
		_status_lbl.text = ""
		_info.text = "[color=#b3a78d]Selecciona una nación en el mapa o en el ranking.[/color]"
		_desc.text = "Las Grandes Potencias pueden ejercer influencia y formar esferas. Las naciones no civilizadas deberán occidentalizarse (reformarse) antes de competir por el rango de potencia."
		_play.disabled = true
		return
	var c: Dictionary = gs.countries[tag]
	_flag.set_flag(c["flag"])
	_name_lbl.text = c["name"]
	_status_lbl.text = "%s  ·  Ranking nº %d" % [VRankingSystem.status_name(c["status"]), int(c["rank"])]
	_status_lbl.add_theme_color_override("font_color", UiTheme.ACCENT if c["status"] == "great_power" else UiTheme.TEXT)
	var allies := []
	for a in c["allies"]:
		allies.append(gs.country_name(a))
	var wars := []
	for w in c["wars"]:
		wars.append("%s (contra %s)" % [w["name"], gs.country_name(w["enemy"])])
	var cap := int(c["capital"])
	var t := ""
	t += _kv("Gobierno", gs.government_name(c["government"]))
	t += _kv("Partido gobernante", "%s (%s)" % [c["ruling_party"]["name"], gs.ideologies.get(c["ruling_party"]["ideology"], {}).get("name", "")])
	t += _kv("Capital", gs.provinces[cap]["name"] if cap > 0 else "—")
	t += _kv("Población", UiTheme.fmt_big(gs.country_population(tag)))
	t += _kv("Provincias / estados", "%d / %d" % [c["provinces"].size(), gs.country_state_instances(tag).size()])
	t += _kv("Cultura principal", gs.culture_name(c["primary_culture"]))
	if not c["accepted_cultures"].is_empty():
		var acc := []
		for a in c["accepted_cultures"]:
			acc.append(gs.culture_name(a))
		t += _kv("Culturas aceptadas", ", ".join(acc))
	t += _kv("Religión oficial", gs.religion_name(c["religion"]))
	t += "\n"
	t += _kv("Prestigio", "%d" % int(c["prestige"]))
	t += _kv("Puntuación industrial", "%d" % int(c["industry_score"]))
	t += _kv("Puntuación militar", "%d" % int(c["military_score"]))
	t += _kv("Puntuación total", "[color=#e8c66f]%d[/color]" % int(c["total_score"]))
	t += "\n"
	t += _kv("Aliados", ", ".join(allies) if not allies.is_empty() else "Ninguno")
	t += _kv("Guerras activas", "[color=#e0705a]%s[/color]" % ", ".join(wars) if not wars.is_empty() else "En paz")
	_info.text = t
	_desc.text = c.get("description", "")
	_play.disabled = false


func _kv(k: String, v: String) -> String:
	return "[color=#b3a78d]%s:[/color]  %s\n" % [k, v]


func _on_center() -> void:
	if selected != "":
		focus_requested.emit(selected)


func _on_play() -> void:
	if selected != "":
		play_pressed.emit(selected)
