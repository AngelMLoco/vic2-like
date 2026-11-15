class_name VTopBar
extends PanelContainer
## Barra superior siempre visible (estilo Victoria II):
## bandera y nación · 8 pestañas · indicadores nacionales · alertas · fecha y velocidades.

signal tab_pressed(tab_id: String)
signal pause_pressed
signal speed_delta(delta: int)
signal menu_pressed
signal flag_pressed

const TABS := [
	["production", "Producción", "F1"], ["budget", "Presupuesto", "F2"], ["technology", "Tecnología", "F3"],
	["politics", "Política", "F4"], ["population", "Población", "F5"], ["trade", "Comercio", "F6"],
	["diplomacy", "Diplomacia", "F7"], ["military", "Militar", "F8"],
]

var gs: VGameState
var _flag: VFlagView
var _name: Label
var _rank: Label
var _stats := {}
var _date: Label
var _pause_icon: VIcon
var _speed_bars: Control
var _tab_buttons := {}
var paused := true
var speed := 2


func setup(state: VGameState) -> void:
	gs = state
	add_theme_stylebox_override("panel", _bar_style())
	anchor_right = 1.0
	offset_bottom = 64
	mouse_filter = Control.MOUSE_FILTER_STOP
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	add_child(hb)

	# nación
	var flag_btn := Button.new()
	flag_btn.flat = true
	flag_btn.custom_minimum_size = Vector2(62, 44)
	flag_btn.tooltip_text = "Centrar en la capital"
	flag_btn.pressed.connect(func(): flag_pressed.emit())
	_flag = VFlagView.create({}, Vector2(60, 40))
	_flag.position = Vector2(1, 2)
	flag_btn.add_child(_flag)
	hb.add_child(flag_btn)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.custom_minimum_size.x = 160
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	_name = UiTheme.label("", 16, UiTheme.ACCENT)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rank = UiTheme.label("", 12, UiTheme.TEXT_DIM)
	nv.add_child(_name)
	nv.add_child(_rank)
	hb.add_child(nv)
	hb.add_child(_vsep())

	# pestañas
	for t in TABS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(50, 50)
		b.tooltip_text = "%s (%s)" % [t[1], t[2]]
		b.pressed.connect(func(): tab_pressed.emit(t[0]))
		var ic := VIcon.create(t[0], 26)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		ic.position = Vector2(12, 4)
		b.add_child(ic)
		var l := UiTheme.label(t[1].substr(0, 5) + ("." if t[1].length() > 5 else ""), 10, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		l.position = Vector2(0, 31)
		l.size = Vector2(50, 16)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		hb.add_child(b)
		_tab_buttons[t[0]] = b
	hb.add_child(_vsep())

	# indicadores
	for s in [["prestige", "Prestigio"], ["budget", "Tesoro"], ["population", "Población"], ["literacy", "Alfabetización"],
			["technology", "Investigación"], ["infamy", "Infamia"], ["exhaustion", "Cansancio bélico"]]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(VIcon.create(s[0], 18, UiTheme.ACCENT if s[0] != "infamy" else UiTheme.NEGATIVE))
		var val := UiTheme.label("—", 14, UiTheme.TEXT)
		box.add_child(val)
		var wrap := PanelContainer.new()
		wrap.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_INSET, Color(0, 0, 0, 0), 0, 3, 5))
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		wrap.add_child(box)
		hb.add_child(wrap)
		_stats[s[0]] = {"value": val, "wrap": wrap}

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)

	var alert := Button.new()
	alert.custom_minimum_size = Vector2(40, 44)
	alert.tooltip_text = "Alertas y notificaciones"
	var aic := VIcon.create("alert", 22)
	aic.position = Vector2(9, 11)
	alert.add_child(aic)
	alert.pressed.connect(func(): tab_pressed.emit("alerts"))
	hb.add_child(alert)
	_stats["alert"] = {"value": null, "wrap": alert}

	# fecha y velocidad
	var tb := PanelContainer.new()
	tb.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.HEADER_DARK, UiTheme.GOLD_DIM, 1, 3, 6))
	hb.add_child(tb)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	tb.add_child(tv)
	_date = UiTheme.label("", 16, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_date.custom_minimum_size.x = 170
	tv.add_child(_date)
	var sh := HBoxContainer.new()
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	sh.add_theme_constant_override("separation", 4)
	tv.add_child(sh)
	var minus := UiTheme.button("-", func(): speed_delta.emit(-1), 26, "Reducir velocidad (tecla -)")
	minus.custom_minimum_size.y = 22
	sh.add_child(minus)
	var pb := Button.new()
	pb.custom_minimum_size = Vector2(32, 22)
	pb.tooltip_text = "Pausa / reanudar (Espacio)"
	pb.pressed.connect(func(): pause_pressed.emit())
	_pause_icon = VIcon.create("play", 14)
	_pause_icon.position = Vector2(9, 4)
	pb.add_child(_pause_icon)
	sh.add_child(pb)
	_speed_bars = Control.new()
	_speed_bars.custom_minimum_size = Vector2(52, 20)
	_speed_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_bars.draw.connect(_draw_speed)
	sh.add_child(_speed_bars)
	var plus := UiTheme.button("+", func(): speed_delta.emit(1), 26, "Aumentar velocidad (tecla +)")
	plus.custom_minimum_size.y = 22
	sh.add_child(plus)
	var menu := UiTheme.button("Menú", func(): menu_pressed.emit(), 0, "Menú del juego (Esc)")
	menu.custom_minimum_size.y = 44
	hb.add_child(menu)


func _bar_style() -> StyleBoxFlat:
	var sb := UiTheme.box(Color("1d1a13"), UiTheme.GOLD, 0, 0, 6)
	sb.border_width_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 5
	return sb


func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = UiTheme.GOLD_DIM
	c.custom_minimum_size = Vector2(1, 44)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _draw_speed() -> void:
	for i in 5:
		var h := 6.0 + i * 3.0
		var r := Rect2(Vector2(i * 10.0 + 2.0, 19.0 - h), Vector2(7.0, h))
		var on := i < speed
		var col := (UiTheme.ACCENT if not paused else UiTheme.GOLD_DIM) if on else Color("3a3426")
		_speed_bars.draw_rect(r, col)


func set_time_state(is_paused: bool, spd: int) -> void:
	paused = is_paused
	speed = spd
	_pause_icon.icon = "play" if paused else "pause"
	_pause_icon.queue_redraw()
	_speed_bars.queue_redraw()
	_date.add_theme_color_override("font_color", UiTheme.NEGATIVE if paused else UiTheme.TEXT)


func refresh() -> void:
	var tag := gs.player_tag
	if tag == "":
		return
	var c: Dictionary = gs.countries[tag]
	_flag.set_flag(c["flag"])
	_name.text = c["name"]
	_name.tooltip_text = c["name"]
	_rank.text = "%s · nº %d" % [VRankingSystem.status_name(c["status"]), int(c["rank"])]
	_date.text = gs.date.text()
	var bal := float(c["income_daily"]) - float(c["expense_daily"])
	_set_stat("prestige", "%d" % int(c["prestige"]), "Prestigio: %d\nPuntuación industrial: %d\nPuntuación militar: %d\nTotal: %d (ranking nº %d)" % [
		int(c["prestige"]), int(c["industry_score"]), int(c["military_score"]), int(c["total_score"]), int(c["rank"])])
	_set_stat("budget", UiTheme.fmt_money(float(c["treasury"])), "Tesoro: %s\nIngresos diarios: %+.1f\nGastos diarios: %.1f\nBalance diario: %+.1f" % [
		UiTheme.fmt_money(float(c["treasury"])), float(c["income_daily"]), float(c["expense_daily"]), bal])
	_stats["budget"]["value"].add_theme_color_override("font_color", UiTheme.POSITIVE if bal >= 0.0 else UiTheme.NEGATIVE)
	var pop := int(c.get("population", gs.country_population(tag)))
	_set_stat("population", UiTheme.fmt_big(pop), "Población total: %s\nProvincias: %d" % [UiTheme.fmt_int(pop), c["provinces"].size()])
	var lit := VPopulationSystem.weighted_average(gs, [int(c["capital"])], "literacy") if int(c["capital"]) > 0 else 0.0
	_set_stat("literacy", "%d%%" % int(round(float(c["literacy"]) * 100.0)), "Alfabetización nacional: %.1f%%\n(capital: %.1f%%)" % [float(c["literacy"]) * 100.0, lit * 100.0])
	_set_stat("technology", "%.1f" % float(c.get("research_points", 0.0)), "Puntos de investigación acumulados: %.1f\nDiarios: %+.2f (clero alfabetizado y gasto en educación)" % [float(c.get("research_points", 0.0)), float(c.get("research_points_daily", 0.0))])
	_set_stat("infamy", "%.1f" % float(c["infamy"]), "Infamia: %.1f / 25\nPor encima de 25 la nación se convierte en paria." % float(c["infamy"]))
	_set_stat("exhaustion", "%.1f" % float(c["war_exhaustion"]), "Cansancio bélico: %.1f" % float(c["war_exhaustion"]))
	var wars: Array = c["wars"]
	_stats["alert"]["wrap"].tooltip_text = "Alertas:\n" + ("· En guerra: %d conflicto(s)\n" % wars.size() if not wars.is_empty() else "") + ("· Balance diario negativo\n" if bal < 0.0 else "") + ("· Sin alertas" if wars.is_empty() and bal >= 0.0 else "")
	var aic: VIcon = _stats["alert"]["wrap"].get_child(0)
	aic.color = UiTheme.NEGATIVE if (not wars.is_empty() or bal < 0.0) else UiTheme.GOLD_DIM
	aic.queue_redraw()


func _set_stat(key: String, value: String, tooltip: String) -> void:
	_stats[key]["value"].text = value
	_stats[key]["wrap"].tooltip_text = tooltip
