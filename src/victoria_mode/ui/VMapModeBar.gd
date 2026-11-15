class_name VMapModeBar
extends PanelContainer
## Panel inferior derecho: leyenda + botones de mapmode + minimapa.

signal mode_selected(mode_id: String)

var minimap: VMinimap
var _buttons := {}
var _legend: HFlowContainer
var _mode_lbl: Label


func setup(gs: VGameState, id_image: Image) -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_right = -10
	offset_bottom = -10
	offset_left = -366
	offset_top = -330
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	_mode_lbl = UiTheme.label("", 14, UiTheme.ACCENT)
	v.add_child(_mode_lbl)
	_legend = HFlowContainer.new()
	_legend.add_theme_constant_override("h_separation", 8)
	v.add_child(_legend)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	v.add_child(grid)
	for m in VMapModes.MODES:
		var b := Button.new()
		b.text = m["name"].substr(0, 4)
		b.custom_minimum_size = Vector2(54, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "%s%s\n%s" % [m["name"], (" (tecla %s)" % m["key"]) if m["key"] != "" else "", m["desc"]]
		b.disabled = not m["available"]
		var id: String = m["id"]
		b.pressed.connect(func(): mode_selected.emit(id))
		grid.add_child(b)
		_buttons[id] = b
	minimap = VMinimap.new()
	minimap.setup(gs, id_image)
	v.add_child(minimap)


func set_active(mode_id: String, legend: Array) -> void:
	var def := VMapModes.mode_def(mode_id)
	_mode_lbl.text = "Mapa: " + def.get("name", mode_id)
	for id in _buttons:
		var b: Button = _buttons[id]
		var on: bool = id == mode_id
		b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.HEADER if on else UiTheme.BUTTON, UiTheme.ACCENT if on else UiTheme.GOLD_DIM, 1, 3, 4))
	for ch in _legend.get_children():
		ch.queue_free()
	for item in legend:
		var hb := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = item[0]
		sw.custom_minimum_size = Vector2(12, 12)
		hb.add_child(sw)
		hb.add_child(UiTheme.label(item[1], 11, UiTheme.TEXT_DIM))
		_legend.add_child(hb)
