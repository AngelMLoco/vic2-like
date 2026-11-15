class_name VGameMenu
extends Control
## Menú del juego (Esc): reanudar, guardar, cargar, volver al menú principal, salir.

signal resume_pressed
signal save_requested(save_name: String)
signal load_requested(path: String)

var _save_name: LineEdit
var _list: ItemList
var _paths: Array = []
var _status: Label


func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UiTheme.title_bar("Menú del juego", func(): resume_pressed.emit()))
	v.add_child(UiTheme.button("Reanudar", func(): resume_pressed.emit()))
	v.add_child(UiTheme.separator())
	v.add_child(UiTheme.label("Guardar partida", 15, UiTheme.GOLD))
	var hb := HBoxContainer.new()
	_save_name = LineEdit.new()
	_save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_name.placeholder_text = "Nombre de la partida"
	hb.add_child(_save_name)
	hb.add_child(UiTheme.button("Guardar", func(): save_requested.emit(_save_name.text), 110))
	v.add_child(hb)
	v.add_child(UiTheme.label("Cargar partida", 15, UiTheme.GOLD))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 160)
	_list.item_activated.connect(func(i): load_requested.emit(_paths[i]))
	v.add_child(_list)
	v.add_child(UiTheme.button("Cargar seleccionada", _on_load))
	_status = UiTheme.label("", 13, UiTheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	v.add_child(UiTheme.separator())
	v.add_child(UiTheme.button("Menú principal", App.goto_main_menu))
	v.add_child(UiTheme.button("Salir del juego", App.quit_game))
	visible = false


func open(default_name: String) -> void:
	visible = true
	_save_name.text = default_name
	_status.text = ""
	_list.clear()
	_paths.clear()
	for info in VSaveSystem.list_saves():
		_list.add_item("%s — %s (%s)" % [info.get("name", "?"), info.get("country_name", "?"), info.get("date_text", "?")])
		_paths.append(info["path"])


func set_status(text: String) -> void:
	_status.text = text


func _on_load() -> void:
	var sel := _list.get_selected_items()
	if not sel.is_empty():
		load_requested.emit(_paths[sel[0]])
