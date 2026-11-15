extends Node
## Raíz del Modo B "Segunda versión".
## Mediador fino entre: estado (VGameState) · simulación (VWorldSimulation + VTimeController)
## · mapa (VWorldMap, VMapLabels, VMapCamera) · interfaz (ui/*).
## No contiene lógica de juego: cada sistema vive en su módulo.

enum Phase { COUNTRY_SELECT, PLAYING }

var gs: VGameState
var sim: VWorldSimulation
var clock: VTimeController
var phase: Phase = Phase.COUNTRY_SELECT

var world_map: VWorldMap
var labels: VMapLabels
var camera: VMapCamera

var ui_root: Control
var top_bar: VTopBar
var province_panel: VProvincePanel
var nation_window: VNationWindow
var mapmode_bar: VMapModeBar
var country_select: VCountrySelect
var game_menu: VGameMenu
var hover_tip: PanelContainer
var hover_lbl: Label
var toast: Label

var selected_province: int = 0
var select_focus_tag: String = ""
var _hover_id: int = 0
var _toast_time: float = 0.0


func _ready() -> void:
	var err := []
	if App.pending_victoria_save != "":
		gs = VSaveSystem.load_game(App.pending_victoria_save, err)
		App.pending_victoria_save = ""
	if gs == null:
		gs = VDataLoader.new_game()
	sim = VWorldSimulation.new(gs)
	clock = VTimeController.new()
	clock.setup(gs.date)
	add_child(clock)
	clock.day_passed.connect(_on_day)
	clock.month_passed.connect(_on_month)
	clock.state_changed.connect(_on_clock_state)
	_build_world()
	_build_ui()
	gs.ownership_changed.connect(func(_ids): _on_ownership_changed())
	if gs.player_tag != "" and gs.countries.has(gs.player_tag):
		_start_playing(gs.player_tag)
		_show_toast("Partida cargada: %s" % gs.date.text())
	else:
		_enter_country_select()
	if not err.is_empty():
		_show_toast(err[0])


# ------------------------------------------------------------------- mundo
func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)
	world_map = VWorldMap.new()
	world_map.setup(gs)
	world.add_child(world_map)
	labels = VMapLabels.new()
	labels.setup(gs)
	world.add_child(labels)
	camera = VMapCamera.new()
	world.add_child(camera)
	camera.make_current()
	camera.setup(world_map.map_size())
	camera.clicked.connect(_on_map_clicked)
	camera.hovered.connect(_on_map_hovered)
	camera.view_changed.connect(_on_view_changed)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui_root = Control.new()
	ui_root.theme = UiTheme.get_theme()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	mapmode_bar = VMapModeBar.new()
	mapmode_bar.setup(gs, world_map.id_image)
	mapmode_bar.mode_selected.connect(set_mapmode)
	mapmode_bar.minimap.navigate.connect(func(pos): camera.center_on(pos))
	ui_root.add_child(mapmode_bar)

	province_panel = VProvincePanel.new()
	province_panel.setup(gs)
	province_panel.closed.connect(func(): _select_province(0))
	province_panel.country_clicked.connect(_focus_country)
	province_panel.state_clicked.connect(_on_state_clicked)
	ui_root.add_child(province_panel)

	nation_window = VNationWindow.new()
	nation_window.setup(gs)
	nation_window.country_focus.connect(func(tag): _set_focus_tag(tag))
	nation_window.province_focus.connect(func(id): _select_province(id, true))
	ui_root.add_child(nation_window)

	country_select = VCountrySelect.new()
	country_select.setup(gs)
	country_select.country_chosen.connect(func(tag): _set_focus_tag(tag))
	country_select.focus_requested.connect(_focus_country)
	country_select.play_pressed.connect(_start_playing)
	country_select.back_pressed.connect(App.goto_main_menu)
	ui_root.add_child(country_select)

	top_bar = VTopBar.new()
	top_bar.setup(gs)
	top_bar.tab_pressed.connect(func(t): nation_window.toggle(t))
	top_bar.pause_pressed.connect(clock.toggle_pause)
	top_bar.speed_delta.connect(func(d): clock.set_speed(clock.speed + d))
	top_bar.menu_pressed.connect(_open_menu)
	top_bar.flag_pressed.connect(func(): _focus_country(gs.player_tag))
	ui_root.add_child(top_bar)

	hover_tip = PanelContainer.new()
	hover_tip.add_theme_stylebox_override("panel", UiTheme.box(Color(0.08, 0.07, 0.05, 0.92), UiTheme.GOLD_DIM, 1, 3, 6))
	hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_lbl = UiTheme.label("", 13)
	hover_tip.add_child(hover_lbl)
	hover_tip.visible = false
	ui_root.add_child(hover_tip)

	toast = UiTheme.label("", 16, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -400
	toast.offset_right = 400
	toast.offset_top = 76
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	toast.add_theme_constant_override("outline_size", 6)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(toast)

	game_menu = VGameMenu.new()
	game_menu.setup()
	game_menu.resume_pressed.connect(func(): game_menu.visible = false)
	game_menu.save_requested.connect(_save)
	game_menu.load_requested.connect(func(path): App.start_victoria(path))
	ui_root.add_child(game_menu)
	set_mapmode("political")
	_on_view_changed()


func _on_state_clicked(_state_id: int) -> void:
	if phase == Phase.PLAYING:
		nation_window.open("production")


# ------------------------------------------------------------------- fases
func _enter_country_select() -> void:
	phase = Phase.COUNTRY_SELECT
	clock.set_paused(true)
	country_select.visible = true
	top_bar.visible = false
	nation_window.visible = false
	province_panel.visible = false
	mapmode_bar.offset_top = -250
	set_mapmode("political")


func _start_playing(tag: String) -> void:
	gs.player_tag = tag
	phase = Phase.PLAYING
	country_select.visible = false
	top_bar.visible = true
	mapmode_bar.offset_top = -330
	_set_focus_tag(tag)
	_on_clock_state(clock.paused, clock.speed)
	top_bar.refresh()
	_focus_country(tag)
	_show_toast("Gobiernas %s. El juego está en pausa: pulsa Espacio para avanzar el tiempo." % gs.country_name(tag))


func _open_menu() -> void:
	clock.set_paused(true)
	game_menu.open("%s_%d" % [gs.player_tag, gs.date.year])


func _save(save_name: String) -> void:
	var path := VSaveSystem.save_game(gs, save_name)
	if path != "":
		game_menu.set_status("Guardado en %s" % path)
		_show_toast("Partida guardada")
	else:
		game_menu.set_status("Error al guardar.")


# ------------------------------------------------------------------- tiempo
func _on_day() -> void:
	sim.on_day()
	top_bar.refresh()
	nation_window.refresh_live()


func _on_month() -> void:
	sim.on_month()
	if world_map.mode in ["population", "industry", "military", "literacy", "culture", "religion"]:
		_recolor()
	province_panel.refresh()
	top_bar.refresh()


func _on_clock_state(paused: bool, spd: int) -> void:
	top_bar.set_time_state(paused, spd)
	top_bar.refresh()


# ------------------------------------------------------------------- mapa
func set_mapmode(mode: String) -> void:
	var def := VMapModes.mode_def(mode)
	if def.is_empty() or not def["available"]:
		_show_toast("%s: %s" % [def.get("name", mode), def.get("desc", "no disponible")])
		return
	world_map.set_mode(mode, _map_focus())
	mapmode_bar.set_active(mode, VMapModes.legend(gs, mode))
	mapmode_bar.minimap.recolor(world_map.colors)


func _recolor() -> void:
	world_map.focus_tag = _map_focus()
	world_map.refresh_colors()
	mapmode_bar.minimap.recolor(world_map.colors)


func _map_focus() -> String:
	return select_focus_tag if select_focus_tag != "" else gs.player_tag


func _set_focus_tag(tag: String) -> void:
	select_focus_tag = tag
	world_map.set_selected(selected_province, tag)
	if phase == Phase.COUNTRY_SELECT:
		country_select.select(tag)
	if world_map.mode == "diplomatic":
		_recolor()


func _on_ownership_changed() -> void:
	world_map.refresh_all()
	labels.rebuild()
	mapmode_bar.minimap.recolor(world_map.colors)


func _on_map_clicked(world_pos: Vector2) -> void:
	var id := world_map.province_at(world_pos)
	if phase == Phase.COUNTRY_SELECT:
		var owner: String = gs.province(id).get("owner", "") if gs.is_land(id) else ""
		_set_focus_tag(owner)
		country_select.select(owner)
		_select_province(id)
		province_panel.visible = false
		return
	_select_province(id)


func _select_province(id: int, center: bool = false) -> void:
	selected_province = id
	world_map.set_selected(id, select_focus_tag)
	if phase == Phase.PLAYING:
		province_panel.show_province(id)
	if center and id > 0:
		camera.center_on(gs.provinces[id]["center"], max(camera.target_zoom, 1.4))


func _focus_country(tag: String) -> void:
	if tag == "" or not gs.countries.has(tag):
		return
	var ids: Array = gs.countries[tag]["provinces"]
	if ids.is_empty():
		return
	var r := Rect2(gs.provinces[ids[0]]["center"], Vector2.ZERO)
	for id in ids:
		r = r.expand(gs.provinces[id]["center"])
	var vs := camera.get_viewport_rect().size
	var z: float = clamp(min(vs.x / max(r.size.x * 1.8, 1.0), vs.y / max(r.size.y * 1.8, 1.0)), camera.min_zoom, 2.2)
	var cap := int(gs.countries[tag]["capital"])
	var target: Vector2 = r.get_center() if r.size.length() < 1200.0 or cap <= 0 else gs.provinces[cap]["center"]
	camera.center_on(target, z)


func _on_map_hovered(world_pos: Vector2) -> void:
	var id := world_map.province_at(world_pos)
	if id != _hover_id:
		_hover_id = id
		world_map.set_hover(id)
	if id <= 0 or game_menu.visible:
		hover_tip.visible = false
		return
	var p: Dictionary = gs.provinces[id]
	var text: String = p["name"]
	if p["kind"] == "land":
		var st: Dictionary = gs.states.get(int(p["state"]), {})
		text += "\n%s · %s" % [st.get("name", ""), gs.country_name(p["owner"])]
		if p["controller"] != p["owner"]:
			text += "\nOcupada por %s" % gs.country_name(p["controller"])
		text += "\nPoblación %s · %s" % [UiTheme.fmt_big(p["population"]), gs.good_name(p["rgo"])]
	else:
		text += "\n" + ("Zona marítima" if p["kind"] == "sea" else "Lago")
	hover_lbl.text = text
	hover_tip.visible = true
	hover_tip.reset_size()
	var mp := ui_root.get_local_mouse_position()
	var vs := ui_root.size
	var pos := mp + Vector2(18, 18)
	if pos.x + hover_tip.size.x > vs.x:
		pos.x = mp.x - hover_tip.size.x - 12
	if pos.y + hover_tip.size.y > vs.y:
		pos.y = mp.y - hover_tip.size.y - 12
	hover_tip.position = pos


func _on_view_changed() -> void:
	var z := camera.current_zoom()
	labels.update_zoom(z)
	world_map.set_border_alphas(clamp((z - 0.45) / 0.9, 0.12, 0.65), clamp((z - 0.3) / 0.5, 0.3, 0.85))
	mapmode_bar.minimap.set_view(camera.visible_rect())


# ------------------------------------------------------------------- input
func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		toast.modulate.a = clamp(_toast_time, 0.0, 1.0)
	camera.input_enabled = not game_menu.visible


func _show_toast(text: String) -> void:
	toast.text = text
	_toast_time = 5.0
	toast.modulate.a = 1.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k == KEY_ESCAPE:
		if game_menu.visible:
			game_menu.visible = false
		elif nation_window.visible:
			nation_window.close()
		elif province_panel.visible:
			_select_province(0)
		elif phase == Phase.PLAYING:
			_open_menu()
		get_viewport().set_input_as_handled()
		return
	if game_menu.visible:
		return
	if phase == Phase.PLAYING:
		if k == KEY_SPACE:
			clock.toggle_pause()
		elif k == KEY_KP_ADD or k == KEY_PLUS or k == KEY_EQUAL:
			clock.faster()
		elif k == KEY_KP_SUBTRACT or k == KEY_MINUS:
			clock.slower()
		elif k == KEY_HOME:
			_focus_country(gs.player_tag)
		elif k >= KEY_F1 and k <= KEY_F8:
			nation_window.toggle(VTopBar.TABS[k - KEY_F1][0])
	for m in VMapModes.MODES:
		if m["key"] != "" and m["available"] and OS.get_keycode_string(k) == m["key"]:
			set_mapmode(m["id"])
			get_viewport().set_input_as_handled()
			return
