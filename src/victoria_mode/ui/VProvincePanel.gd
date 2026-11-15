class_name VProvincePanel
extends PanelContainer
## Ventana de provincia (abajo a la izquierda, como en Victoria II).
## Separa explícitamente PROPIETARIO (legal) y CONTROLADOR (militar).

signal closed
signal country_clicked(tag: String)
signal state_clicked(state_id: int)

var gs: VGameState
var province_id: int = 0
var _title: Label
var _subtitle: Label
var _flag: VFlagView
var _owner_btn: Button
var _body: RichTextLabel
var _pop_bar: VStackBar
var _culture_bar: VStackBar
var _ideology_bar: VStackBar
var _occupation: ProgressBar
var _occ_row: Control


func setup(state: VGameState) -> void:
	gs = state
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10
	offset_right = 450
	offset_top = -560
	offset_bottom = -10
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	# cabecera
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiTheme.header_box())
	v.add_child(head)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	head.add_child(hb)
	_owner_btn = Button.new()
	_owner_btn.flat = true
	_owner_btn.custom_minimum_size = Vector2(54, 36)
	_owner_btn.pressed.connect(func(): if_owner())
	_flag = VFlagView.create({}, Vector2(52, 34))
	_flag.position = Vector2(1, 1)
	_owner_btn.add_child(_flag)
	hb.add_child(_owner_btn)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = UiTheme.label("", 19, UiTheme.ACCENT)
	_title.clip_text = true
	_subtitle = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_STOP
	_subtitle.gui_input.connect(_on_subtitle_input)
	tv.add_child(_title)
	tv.add_child(_subtitle)
	hb.add_child(tv)
	var close := UiTheme.button("×", func(): closed.emit(), 30, "Cerrar")
	hb.add_child(close)
	# ocupación
	_occ_row = HBoxContainer.new()
	var ol := UiTheme.label("Ocupación", 13, UiTheme.NEGATIVE)
	ol.custom_minimum_size.x = 90
	_occ_row.add_child(ol)
	_occupation = ProgressBar.new()
	_occupation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_occupation.custom_minimum_size.y = 16
	_occ_row.add_child(_occupation)
	v.add_child(_occ_row)
	# cuerpo
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 13)
	_body.add_theme_font_size_override("bold_font_size", 13)
	inner.add_child(_body)
	inner.add_child(UiTheme.label("Fuerza laboral (POPs)", 13, UiTheme.GOLD))
	_pop_bar = VStackBar.create(16)
	inner.add_child(_pop_bar)
	inner.add_child(UiTheme.label("Culturas", 13, UiTheme.GOLD))
	_culture_bar = VStackBar.create(12)
	inner.add_child(_culture_bar)
	inner.add_child(UiTheme.label("Ideologías", 13, UiTheme.GOLD))
	_ideology_bar = VStackBar.create(12)
	inner.add_child(_ideology_bar)
	visible = false


func if_owner() -> void:
	var p := gs.province(province_id)
	if not p.is_empty() and p.get("owner", "") != "":
		country_clicked.emit(p["owner"])


func _on_subtitle_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var p := gs.province(province_id)
		if not p.is_empty() and int(p.get("state", 0)) > 0:
			state_clicked.emit(int(p["state"]))


func show_province(id: int) -> void:
	province_id = id
	visible = id > 0
	if id > 0:
		refresh()


func refresh() -> void:
	if province_id <= 0 or not visible:
		return
	var p := gs.province(province_id)
	if p.is_empty():
		return
	if p["kind"] != "land":
		_show_water(p)
		return
	var owner: String = p["owner"]
	var controller: String = p["controller"]
	var st: Dictionary = gs.states.get(int(p["state"]), {})
	_title.text = p["name"]
	var split := " · estado dividido" if gs.state_is_split(int(p["state"])) else ""
	_subtitle.text = "Estado: %s%s" % [st.get("name", "—"), split]
	_subtitle.tooltip_text = "Clic: ver el estado en la ventana de Producción"
	if owner != "":
		_flag.set_flag(gs.countries[owner]["flag"])
		_owner_btn.tooltip_text = gs.country_name(owner)
	else:
		_flag.clear_flag()
		_owner_btn.tooltip_text = "Territorio no colonizado"
	var occupied: bool = controller != owner
	_occ_row.visible = occupied or float(p.get("occupation", 0.0)) > 0.0
	_occupation.value = 100.0 if occupied else float(p.get("occupation", 0.0)) * 100.0

	var t := ""
	var is_capital := owner != "" and int(gs.countries[owner]["capital"]) == province_id
	t += _kv("Propietario", _country_link(owner) + ("  [color=#e8c66f](capital nacional)[/color]" if is_capital else ""))
	t += _kv("Controlador", _country_link(controller) + ("  [color=#e0705a](ocupada)[/color]" if occupied else ""))
	var cores := []
	for c in p.get("cores", []):
		cores.append(gs.country_name(c))
	t += _kv("Cores", ", ".join(cores) if not cores.is_empty() else "Ninguno")
	t += "\n"
	var pop := int(p["population"])
	t += _kv("Población", "%s  [color=#7f7562](%.1f hab/km²)[/color]" % [UiTheme.fmt_int(pop), float(pop) / max(1.0, float(p["area_km2"]))])
	t += _kv("Terreno", gs.terrain_name(p["terrain"]))
	t += _kv("Life rating", "%d" % int(p["life_rating"]))
	var good: Dictionary = gs.goods.get(p["rgo"], {})
	var workers := 0
	var worker_type := "farmers" if good.get("rgo", "farm") == "farm" else "labourers"
	for pp in p["pops"]:
		if pp["type"] == worker_type:
			workers += int(pp["size"])
	var eff := float(gs.terrain_types.get(p["terrain"], {}).get("rgo_efficiency", 1.0))
	var output := float(workers) / 40000.0 * eff * (1.0 + 0.1 * int(p["infrastructure"]))
	t += _kv("RGO", "[color=#%s]■[/color] %s  ·  %s %s" % [good.get("color", "ffffff"), good.get("name", p["rgo"]), UiTheme.fmt_int(workers), gs.pop_type_name(worker_type).to_lower()])
	t += _kv("Producción RGO", "%.2f unidades/día  [color=#7f7562](precio base %.1f)[/color]" % [output, float(good.get("base_price", 0.0))])
	t += _kv("Infraestructura", "%d" % int(p["infrastructure"]))
	t += _kv("Fortificación", "%d" % int(p["fort"]))
	t += _kv("Base naval", ("%d" % int(p["naval_base"])) if p["coastal"] else "— (interior)")
	t += "\n"
	var cult := VPopulationSystem.sizes_by(gs, [province_id], "culture")
	var rel := VPopulationSystem.sizes_by(gs, [province_id], "religion")
	t += _kv("Culturas", _shares(cult, func(k): return gs.culture_name(k)))
	t += _kv("Religiones", _shares(rel, func(k): return gs.religion_name(k)))
	var mil := VPopulationSystem.weighted_average(gs, [province_id], "militancy")
	var con := VPopulationSystem.weighted_average(gs, [province_id], "consciousness")
	var lit := VPopulationSystem.weighted_average(gs, [province_id], "literacy")
	t += _kv("Militancia", "%.2f" % mil)
	t += _kv("Conciencia", "%.2f" % con)
	t += _kv("Alfabetización", "%.1f%%" % (lit * 100.0))
	var types := VPopulationSystem.sizes_by(gs, [province_id], "type")
	t += _kv("Soldier POPs", "%s soldados  ·  %s oficiales" % [UiTheme.fmt_int(types.get("soldiers", 0)), UiTheme.fmt_int(types.get("officers", 0))])
	t += _kv("Ejércitos presentes", "Ninguno")
	_body.text = t

	var segs := []
	for k in types:
		segs.append([types[k], gs.pop_types.get(k, {}).get("color_obj", Color.GRAY), gs.pop_type_name(k)])
	segs.sort_custom(func(a, b): return a[0] > b[0])
	_pop_bar.set_segments(segs)
	var csegs := []
	for k in cult:
		csegs.append([cult[k], gs.cultures.get(k, {}).get("color_obj", Color.GRAY), gs.culture_name(k)])
	_culture_bar.set_segments(csegs)
	var ideo := VPopulationSystem.ideology_mix(gs, [province_id])
	var isegs := []
	for k in ideo:
		isegs.append([ideo[k], gs.ideologies.get(k, {}).get("color_obj", Color.GRAY), gs.ideologies.get(k, {}).get("name", k)])
	_ideology_bar.set_segments(isegs)
	_pop_bar.visible = true
	_culture_bar.visible = true
	_ideology_bar.visible = true


func _show_water(p: Dictionary) -> void:
	_title.text = p["name"]
	_subtitle.text = "Zona marítima" if p["kind"] == "sea" else "Lago"
	_flag.clear_flag()
	_occ_row.visible = false
	var coasts := []
	for n in p["neighbors"]:
		if gs.is_land(n):
			coasts.append(gs.provinces[n]["name"])
	var seas := 0
	for n in p["neighbors"]:
		if n >= gs.first_sea_id and n < gs.first_lake_id:
			seas += 1
	var t := _kv("Tipo", "Zona marítima navegable" if p["kind"] == "sea" else "Lago (no navegable)")
	t += _kv("Superficie", "%s km²" % UiTheme.fmt_int(p["area_km2"]))
	t += _kv("Zonas marítimas vecinas", str(seas))
	t += _kv("Costas", ", ".join(coasts.slice(0, 12)) + (" …" if coasts.size() > 12 else "") if not coasts.is_empty() else "Mar abierto")
	t += _kv("Flotas presentes", "Ninguna")
	_body.text = t
	_pop_bar.set_segments([])
	_culture_bar.set_segments([])
	_ideology_bar.set_segments([])


func _country_link(tag: String) -> String:
	if tag == "":
		return "[color=#9a9078]Sin colonizar[/color]"
	return "[color=#%s]■[/color] %s" % [gs.countries[tag]["color"], gs.country_name(tag)]


func _shares(d: Dictionary, namer: Callable) -> String:
	var total := 0
	for k in d:
		total += int(d[k])
	var keys := d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var parts := []
	for k in keys.slice(0, 3):
		parts.append("%s %.0f%%" % [namer.call(k), float(d[k]) / max(1.0, float(total)) * 100.0])
	return ", ".join(parts)


func _kv(k: String, v: String) -> String:
	return "[color=#b3a78d]%s:[/color] %s\n" % [k, v]
