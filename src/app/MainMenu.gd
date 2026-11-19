extends Control
## Menú principal: Nuevo juego / Cargar partida / Opciones / Salir,
## y selector de modo (Prototipo actual / Segunda versión).


var _pages := {}
var _load_list: ItemList
var _load_paths: Array[String] = []
var _load_info: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_layout()
	_show_page("main")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_show_page("main")


# ------------------------------------------------------------------ fondo
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# fondo: mapa del mundo del escenario por defecto
	var map_tex := VWorlds.default_map_texture()
	if not FileAccess.file_exists(map_tex):
		return
	var img := VWorldMap.load_id_image(map_tex)
	img.resize(img.get_width() / 4, img.get_height() / 4, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	var first_sea := 1 << 30
	var meta := VJson.load_dict(map_tex.get_base_dir() + "/map.json")
	if meta.has("first_sea_id"):
		first_sea = int(meta["first_sea_id"])
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/app/menu_background.gdshader")
	mat.set_shader_parameter("first_sea_id", first_sea)
	tr.material = mat
	add_child(tr)
	var vignette := ColorRect.new()
	vignette.color = Color(0.05, 0.04, 0.03, 0.35)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


# ---------------------------------------------------------------- páginas
func _build_layout() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)

	var title := UiTheme.label("CHRONICLES OF AETHER", 54, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	var sub := UiTheme.label("Gran estrategia · prototipo de simulación", 18, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	sub.add_theme_constant_override("outline_size", 6)
	col.add_child(sub)

	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(560, 0)
	col.add_child(holder)
	var stack := VBoxContainer.new()
	holder.add_child(stack)

	_pages["main"] = _page_main()
	_pages["mode"] = _page_mode()
	_pages["scenario"] = _page_scenario()
	_pages["load"] = _page_load()
	_pages["options"] = _page_options()
	for p in _pages.values():
		stack.add_child(p)

	var foot := UiTheme.label("Modo A: prototipo congelado como referencia  ·  Modo B: reconstrucción estilo Victoria II", 13, UiTheme.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(foot)


func _menu_button(text: String, cb: Callable, tooltip: String = "") -> Button:
	var b := UiTheme.button(text, cb, 0, tooltip)
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 21)
	return b


func _page_main() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(_menu_button("NUEVO JUEGO", func(): _show_page("mode")))
	v.add_child(_menu_button("CARGAR PARTIDA", func(): _refresh_load_list(); _show_page("load")))
	v.add_child(_menu_button("OPCIONES", func(): _show_page("options")))
	v.add_child(_menu_button("SALIR", App.quit_game))
	return v


func _page_mode() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(UiTheme.title_bar("Elige modo"))
	var a := _menu_button("PROTOTIPO ACTUAL", App.start_legacy, "Modo A: el prototipo existente, conservado sin cambios funcionales.")
	v.add_child(a)
	v.add_child(UiTheme.label("Simulación original de 30 provincias: POPs, mercado, guerras abstractas. Congelado como referencia.", 13, UiTheme.TEXT_DIM))
	var b := _menu_button("SEGUNDA VERSIÓN", func(): _show_page("scenario"), "Modo B: reconstrucción estilo Victoria II. Elige escenario y después nación.")
	v.add_child(b)
	v.add_child(UiTheme.label("Escenario → nación → jugar. El escenario elige el mundo (mapa, países, culturas, religiones).", 13, UiTheme.TEXT_DIM))
	v.add_child(UiTheme.button("Volver", func(): _show_page("main")))
	return v


## M6: escenarios jugables (habilitados, con un mundo válido y no reservados a pruebas). Un mundo en
## desarrollo (p. ej. Chronicles of Aether sin datos) no aparece.
func _page_scenario() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(UiTheme.title_bar("Elige escenario"))
	var list := VWorlds.playable_scenarios()
	if list.is_empty():
		v.add_child(UiTheme.label("No hay escenarios disponibles.", 14, UiTheme.TEXT_DIM))
	for sc in list:
		var sid := String(sc["id"])
		var meta := VWorlds.world_meta(VWorlds.world_of(sc))
		var b := _menu_button(String(sc.get("name", sid)).to_upper(), func(): App.start_victoria("", sid), String(meta.get("description", "")))
		v.add_child(b)
		var d := UiTheme.label("%s · %s" % [String(meta.get("name", "")), String(sc.get("description", ""))], 13, UiTheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	v.add_child(UiTheme.button("Volver", func(): _show_page("mode")))
	return v


func _page_load() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiTheme.title_bar("Cargar partida"))
	v.add_child(UiTheme.label("Segunda versión", 16, UiTheme.ACCENT))
	_load_list = ItemList.new()
	_load_list.custom_minimum_size = Vector2(0, 220)
	_load_list.item_selected.connect(_on_load_selected)
	_load_list.item_activated.connect(func(_i): _load_selected())
	v.add_child(_load_list)
	_load_info = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	_load_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_load_info)
	var hb := HBoxContainer.new()
	hb.add_child(UiTheme.button("Cargar", _load_selected, 140))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	hb.add_child(UiTheme.button("Volver", func(): _show_page("main"), 120))
	v.add_child(hb)
	v.add_child(UiTheme.separator())
	v.add_child(UiTheme.label("Prototipo actual", 16, UiTheme.ACCENT))
	v.add_child(UiTheme.label("Sus partidas se cargan desde su propio botón «Cargar» dentro del modo.", 13, UiTheme.TEXT_DIM))
	v.add_child(UiTheme.button("Abrir prototipo actual", App.start_legacy))
	return v


func _page_options() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiTheme.title_bar("Opciones"))
	var fs := CheckBox.new()
	fs.text = "Pantalla completa"
	fs.button_pressed = App.settings.get("fullscreen", false)
	fs.toggled.connect(func(on): App.set_setting("fullscreen", on))
	v.add_child(fs)
	var es := CheckBox.new()
	es.text = "Desplazar el mapa al acercar el cursor a los bordes"
	es.button_pressed = App.settings.get("edge_scroll", true)
	es.toggled.connect(func(on): App.set_setting("edge_scroll", on))
	v.add_child(es)
	v.add_child(_slider_row("Escala de interfaz", 0.75, 1.5, 0.05, float(App.settings.get("ui_scale", 1.0)), func(x): App.set_setting("ui_scale", x)))
	v.add_child(_slider_row("Velocidad de cámara", 0.5, 2.0, 0.1, float(App.settings.get("camera_speed", 1.0)), func(x): App.set_setting("camera_speed", x)))
	v.add_child(UiTheme.button("Volver", func(): _show_page("main")))
	return v


func _slider_row(text: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	var l := UiTheme.label(text, 15)
	l.custom_minimum_size.x = 210
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 22
	var val := UiTheme.label("%.2f" % value, 14, UiTheme.TEXT_DIM)
	val.custom_minimum_size.x = 48
	s.drag_ended.connect(func(_c): cb.call(s.value))
	s.value_changed.connect(func(x): val.text = "%.2f" % x)
	hb.add_child(s)
	hb.add_child(val)
	return hb


func _show_page(page: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page


func _refresh_load_list() -> void:
	_load_list.clear()
	_load_paths.clear()
	for info in VSaveSystem.list_saves():
		_load_list.add_item("%s   —   %s   (%s · %s)" % [info.get("name", "?"), info.get("country_name", "?"), info.get("date_text", "?"), info.get("world_name", "Prototipo terrestre")])
		_load_paths.append(info.get("path", ""))
	_load_info.text = "No hay partidas guardadas de la Segunda versión." if _load_paths.is_empty() else "Selecciona una partida."


func _on_load_selected(i: int) -> void:
	_load_info.text = _load_paths[i]


func _load_selected() -> void:
	var sel := _load_list.get_selected_items()
	if sel.is_empty():
		return
	App.start_victoria(_load_paths[sel[0]])
