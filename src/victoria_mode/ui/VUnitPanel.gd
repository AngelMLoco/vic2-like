class_name VUnitPanel
extends PanelContainer
## Panel de la unidad seleccionada (abajo a la izquierda): ejército(s) o flota.
## Órdenes: detener, fusionar, dividir, reorganizar, general, embarcar; flota: puerto, desembarcar.
## El movimiento se ordena con clic derecho en el mapa (Mayús = encolar).

signal closed
signal changed

var gs: VGameState
var armies: Array = []  # ids
var fleet_id: int = 0
var _title: Label
var _body: RichTextLabel
var _actions: HFlowContainer
var _msg: Label


func setup(state: VGameState) -> void:
	gs = state
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10
	offset_right = 470
	offset_top = -470
	offset_bottom = -10
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiTheme.header_box())
	var hb := HBoxContainer.new()
	head.add_child(hb)
	_title = UiTheme.label("", 17, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	hb.add_child(_title)
	hb.add_child(UiTheme.button("×", func(): closed.emit(), 30, "Cerrar (Esc)"))
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 13)
	scroll.add_child(_body)
	_actions = HFlowContainer.new()
	v.add_child(_actions)
	_msg = UiTheme.label("", 12, UiTheme.ACCENT)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_msg)
	visible = false


func show_armies(ids: Array) -> void:
	armies = ids.duplicate()
	fleet_id = 0
	_msg.text = ""
	visible = not armies.is_empty()
	refresh()


func show_fleet(id: int) -> void:
	fleet_id = id
	armies = []
	_msg.text = ""
	visible = id > 0
	refresh()


func message(text: String) -> void:
	_msg.text = text


func refresh() -> void:
	if not visible:
		return
	for ch in _actions.get_children():
		ch.queue_free()
	if fleet_id > 0:
		_refresh_fleet()
	else:
		_refresh_armies()


func _alive_armies() -> Array:
	var out := []
	for aid in armies:
		if gs.armies.has(int(aid)):
			out.append(gs.armies[int(aid)])
	armies = []
	for a in out:
		armies.append(int(a["id"]))
	return out


func _refresh_armies() -> void:
	var list := _alive_armies()
	if list.is_empty():
		visible = false
		closed.emit()
		return
	var a: Dictionary = list[0]
	var own: bool = a["country"] == gs.player_tag and int(a.get("rebel_faction", 0)) == 0
	_title.text = a["name"] if list.size() == 1 else "%d ejércitos seleccionados" % list.size()
	var t := ""
	for army in list:
		var men := VArmySystem.army_strength(gs, army)
		var maxm: int = army["brigades"].size() * gs.unit_manpower
		var where: String = gs.provinces[int(army["province"])]["name"]
		var status := "En %s" % where
		if int(army["battle"]) > 0:
			status = "[color=#e0705a]En combate en %s[/color]" % where
		elif army.get("retreating", false):
			status = "[color=#e0705a]En retirada[/color]"
		elif int(army["embarked"]) > 0:
			status = "Embarcado en %s" % gs.fleets.get(int(army["embarked"]), {}).get("name", "?")
		elif not army["path"].is_empty():
			status = "En marcha hacia %s (%d provincias)" % [gs.provinces[int(army["path"][-1])]["name"], army["path"].size()]
		var owner_txt := gs.country_name(army["country"]) if int(army.get("rebel_faction", 0)) == 0 else "Rebeldes"
		t += "[b]%s[/b] · %s · %s\n" % [army["name"], owner_txt, status]
		t += "  Hombres %s / %s · organización %.0f%% · moral %.0f%% · suministro %.0f%%\n" % [UiTheme.fmt_int(men), UiTheme.fmt_int(maxm),
			VArmySystem.army_organisation(gs, army) * 100.0, float(army.get("morale", 1.0)) * 100.0, float(army.get("supply", 1.0)) * 100.0]
		var lim := VSupplySystem.supply_limit(gs, army["country"], int(army["province"]))
		t += "  Límite de suministro aquí: %.0f brigadas · atrincherado %d días\n" % [lim, int(army.get("dig_in", 0))]
		var l: Dictionary = gs.leaders.get(int(army.get("leader", 0)), {})
		t += "  General: %s\n" % (VLeaderSystem.describe(gs, l) if not l.is_empty() else "ninguno")
		if list.size() == 1:
			for bid in army["brigades"]:
				var b: Dictionary = gs.brigades.get(bid, {})
				if b.is_empty():
					continue
				var pop_s := VArmySystem.find_pop(gs, int(b["source_province_id"]), int(b["source_pop_id"]))
				t += "  · %s: %s hombres · org %.0f%% · exp %.0f%% · reclutada de %s (%s soldados)\n" % [gs.unit_types.get(b["type"], {}).get("name", b["type"]),
					UiTheme.fmt_int(b["strength"]), float(b["organisation"]) * 100.0, float(b.get("experience", 0.0)) * 100.0,
					gs.provinces[int(b["source_province_id"])]["name"], UiTheme.fmt_int(gs.pops.size[pop_s] if pop_s >= 0 else 0)]
	_body.text = t
	if not own:
		return
	_btn("Detener", func():
		for x in _alive_armies():
			VArmySystem.stop(x)
		changed.emit(), "Cancela la orden de movimiento")
	if list.size() > 1:
		_btn("Fusionar", func():
			_msg.text = VArmySystem.merge(gs, list[0], list.slice(1))
			armies = [int(list[0]["id"])]
			changed.emit(), "Une los ejércitos seleccionados (misma provincia)")
	if list.size() == 1:
		_btn("Dividir", func():
			var na := VArmySystem.split(gs, a)
			_msg.text = "" if not na.is_empty() else "No se puede dividir (necesita 2+ brigadas y estar fuera de combate)."
			changed.emit(), "Divide el ejército en dos")
		_btn("Reorganizar", func():
			var na2 := VArmySystem.reorganise(gs, a)
			_msg.text = "Brigadas dañadas separadas en una reserva." if not na2.is_empty() else "No hay brigadas muy dañadas que separar."
			changed.emit(), "Separa las brigadas con menos del 50 % de hombres")
		if int(a["leader"]) > 0:
			_btn("Retirar general", func():
				VArmySystem.detach_leader(gs, a)
				changed.emit(), "")
		else:
			for lid in gs.leaders:
				var l2: Dictionary = gs.leaders[lid]
				if l2["country"] == a["country"] and l2["kind"] == "general" and int(l2.get("army", 0)) == 0:
					_btn("Asignar %s" % l2["name"], func():
						_msg.text = VArmySystem.attach_leader(gs, a, int(lid))
						changed.emit(), VLeaderSystem.describe(gs, l2))
					break
		if int(a["embarked"]) == 0:
			for f in VNavySystem.country_fleets(gs, a["country"]):
				var why := VNavySystem.can_load(gs, a, f)
				var b2 := _btn("Embarcar en %s" % f["name"], func():
					_msg.text = VNavySystem.load_army(gs, a, f)
					changed.emit(), why if why != "" else "Capacidad libre: %d brigadas" % (VNavySystem.capacity(gs, f) - VNavySystem.carried_brigades(gs, f)))
				b2.disabled = why != ""
				break
		else:
			_msg.text = "Embarcado: mueve la flota y haz clic derecho en una costa vecina para desembarcar."


func _refresh_fleet() -> void:
	var f: Dictionary = gs.fleets.get(fleet_id, {})
	if f.is_empty():
		visible = false
		closed.emit()
		return
	_title.text = f["name"]
	var loc := int(f["location"])
	var t := "%s · %s\n" % [gs.country_name(f["country"]), ("Atracada en %s" if gs.is_land(loc) else "En %s") % gs.provinces[loc]["name"]]
	if not f["path"].is_empty():
		t += "Navegando hacia %s (%d zonas)\n" % [gs.provinces[int(f["path"][-1])]["name"], f["path"].size()]
	t += "Misión: %s · transporte %d / %d brigadas\n" % [f.get("mission", "idle"), VNavySystem.carried_brigades(gs, f), VNavySystem.capacity(gs, f)]
	var adm: Dictionary = gs.leaders.get(int(f.get("admiral", 0)), {})
	t += "Almirante: %s\n" % (VLeaderSystem.describe(gs, adm) if not adm.is_empty() else "ninguno")
	var counts := {}
	for s in f["ships"]:
		var e: Array = counts.get(s["type"], [0, 0.0])
		e[0] += 1
		e[1] += float(s["hull"])
		counts[s["type"]] = e
	for k in counts:
		t += "  · %d × %s (casco medio %.0f%%)\n" % [counts[k][0], gs.ship_types.get(k, {}).get("name", k), float(counts[k][1]) / float(counts[k][0]) * 100.0]
	for aid in f["transported_armies"]:
		var a: Dictionary = gs.armies.get(aid, {})
		if not a.is_empty():
			t += "  ⤷ transporta %s (%d brigadas)\n" % [a["name"], a["brigades"].size()]
	_body.text = t
	if f["country"] != gs.player_tag:
		return
	_btn("Volver a puerto", func():
		var port := VNavySystem.nearest_port(gs, f)
		_msg.text = VNavySystem.order_move(gs, f, port) if port > 0 else "No hay puerto accesible."
		changed.emit(), "Navega al puerto propio más cercano para reparar")
	_btn("Detener", func():
		f["path"] = []
		changed.emit(), "")
	if not f["transported_armies"].is_empty():
		_msg.text = "Clic derecho en una costa vecina para desembarcar las tropas."


func _btn(text: String, cb: Callable, tip: String) -> Button:
	var b := UiTheme.button(text, cb, 0, tip)
	b.add_theme_font_size_override("font_size", 13)
	_actions.add_child(b)
	return b
