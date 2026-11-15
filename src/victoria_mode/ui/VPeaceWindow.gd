class_name VPeaceWindow
extends PanelContainer
## Ventana de guerra y negociación de paz.
## Muestra el warscore con su desglose, los objetivos de guerra, permite añadir objetivos válidos y
## proponer la paz en dos modos (exigir / ofrecer) seleccionando objetivos, con coste total y
## probabilidad de aceptación de la IA con sus razones. También responde a ofertas de la IA.

signal closed
signal changed

var gs: VGameState
var war_id: int = 0
var mode: String = "demand"
var _selected := {}
var _content: VBoxContainer
var _title: Label
var _msg: Label


func setup(state: VGameState) -> void:
	gs = state
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -430
	offset_right = 430
	offset_top = -320
	offset_bottom = 330
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var bar := UiTheme.title_bar("Guerra", func(): close())
	_title = bar.get_child(0).get_child(0)
	v.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)
	_msg = UiTheme.label("", 13, UiTheme.ACCENT)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_msg)
	visible = false


func open(wid: int) -> void:
	war_id = wid
	_selected.clear()
	mode = "demand"
	_msg.text = ""
	visible = true
	rebuild()


func close() -> void:
	visible = false
	closed.emit()


func _lbl(text: String, size: int = 14, col: Color = UiTheme.TEXT) -> Label:
	var l := UiTheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)
	return l


func rebuild() -> void:
	for ch in _content.get_children():
		ch.queue_free()
	var w: Dictionary = gs.wars.get(war_id, {})
	if w.is_empty():
		_title.text = "GUERRA TERMINADA"
		_lbl("Esta guerra ya ha terminado.")
		return
	var me := gs.player_tag
	_title.text = w["name"].to_upper()
	var names_a := []
	for t in w["attackers"]:
		names_a.append(gs.country_name(t))
	var names_d := []
	for t in w["defenders"]:
		names_d.append(gs.country_name(t))
	_lbl("Atacantes: %s\nDefensores: %s\nDesde %s" % [", ".join(names_a), ", ".join(names_d), w.get("start", "")], 13, UiTheme.TEXT_DIM)
	var ws := VWarSystem.warscore_for(w, me)
	var sign := 1.0 if VWarSystem.side_of(w, me) == "attackers" else -1.0
	_lbl("WARSCORE (para ti): %+.1f" % ws, 18, UiTheme.POSITIVE if ws >= 0 else UiTheme.NEGATIVE)
	_lbl("   batallas %+.1f · ocupación %+.1f · bloqueo %+.1f · objetivos (ticking) %+.1f" % [float(w["battle_ws"]) * sign,
		float(w["occupation_ws"]) * sign, float(w["blockade_ws"]) * sign, float(w["ticking_ws"]) * sign], 13, UiTheme.TEXT_DIM)
	_lbl("Cansancio bélico propio: %.1f" % float(gs.countries[me].get("war_exhaustion", 0.0)), 13, UiTheme.TEXT_DIM)
	# oferta pendiente de la IA
	var off: Dictionary = w.get("offer", {})
	if not off.is_empty():
		_content.add_child(UiTheme.separator())
		var gnames := []
		for g in off["goals"]:
			gnames.append(VCasusBelliSystem.goal_name(gs, g))
		_lbl("%s %s: %s" % [gs.country_name(off["from"]), "EXIGE" if off["mode"] == "demand" else "OFRECE", ", ".join(gnames) if not gnames.is_empty() else "paz blanca"], 15, UiTheme.ACCENT)
		var hb0 := HBoxContainer.new()
		hb0.add_child(UiTheme.button("Aceptar", func():
			VPeaceSystem.answer_offer(gs, w, true)
			changed.emit()
			rebuild()))
		hb0.add_child(UiTheme.button("Rechazar", func():
			VPeaceSystem.answer_offer(gs, w, false)
			changed.emit()
			rebuild()))
		_content.add_child(hb0)
	_content.add_child(UiTheme.separator())
	_lbl("OBJETIVOS DE GUERRA", 14, UiTheme.GOLD)
	for g in w["war_goals"]:
		_lbl("· %s — coste %.0f" % [VCasusBelliSystem.goal_name(gs, g), VPeaceSystem.goal_cost(gs, g)], 13)
	# añadir objetivos
	var my_side := VWarSystem.side_of(w, me)
	var adds := []
	for e in VWarSystem.enemies_in_war(gs, w, me):
		for cb_id in gs.cb_types:
			var d: Dictionary = gs.cb_types[cb_id]
			if int(d.get("justify_months", 0)) == 0 and cb_id != "restore_core":
				continue
			if d.get("scope", "") == "state":
				for sid in VCasusBelliSystem.bordering_states(gs, me, e).slice(0, 4):
					adds.append([cb_id, e, sid])
			else:
				adds.append([cb_id, e, 0])
	if not adds.is_empty():
		_lbl("Añadir objetivo:", 13, UiTheme.TEXT_DIM)
		var flow := HFlowContainer.new()
		for ad in adds.slice(0, 16):
			var chk := VWarSystem.can_add_wargoal(gs, war_id, me, ad[0], ad[1], ad[2])
			var label: String = gs.cb_types[ad[0]]["name"] + (": " + gs.states[ad[2]]["name"] if ad[2] > 0 else " (" + VMapLabels.short_name(gs.country_name(ad[1])) + ")")
			var b := UiTheme.button(label, func():
				_msg.text = VWarSystem.add_wargoal(gs, war_id, me, ad[0], ad[1], ad[2])
				rebuild(), 0, ("Infamia +%.1f" % float(chk["infamy"])) if chk["ok"] else chk["reason"])
			b.disabled = not chk["ok"]
			b.add_theme_font_size_override("font_size", 12)
			flow.add_child(b)
		_content.add_child(flow)
	# negociación
	_content.add_child(UiTheme.separator())
	_lbl("NEGOCIAR LA PAZ", 14, UiTheme.GOLD)
	var hb := HBoxContainer.new()
	var bd := UiTheme.button("Exigir condiciones", func():
		mode = "demand"
		_selected.clear()
		rebuild())
	var bo := UiTheme.button("Ofrecer condiciones", func():
		mode = "offer"
		_selected.clear()
		rebuild())
	bd.disabled = mode == "demand"
	bo.disabled = mode == "offer"
	hb.add_child(bd)
	hb.add_child(bo)
	_content.add_child(hb)
	var side_for_goals := my_side if mode == "demand" else ("defenders" if my_side == "attackers" else "attackers")
	var avail := VPeaceSystem.goals_for_side(gs, w, side_for_goals)
	if avail.is_empty():
		_lbl("No hay objetivos que %s en esta guerra (solo paz blanca)." % ("exigir" if mode == "demand" else "conceder"), 13, UiTheme.TEXT_DIM)
	for g in avail:
		var cb := CheckBox.new()
		cb.text = "%s — coste %.0f" % [VCasusBelliSystem.goal_name(gs, g), VPeaceSystem.goal_cost(gs, g)]
		cb.button_pressed = _selected.has(int(g["id"]))
		cb.toggled.connect(func(on):
			if on:
				_selected[int(g["id"])] = g
			else:
				_selected.erase(int(g["id"]))
			rebuild())
		_content.add_child(cb)
	var goals: Array = _selected.values()
	var ev := VPeaceSystem.evaluate(gs, w, me, mode, goals)
	_lbl("Warscore disponible %+.0f · coste total %.0f · probabilidad de aceptación %.0f%%" % [ws, float(ev["cost"]), float(ev["chance"])], 15,
		UiTheme.POSITIVE if ev["accept"] else UiTheme.NEGATIVE)
	_lbl("Razones de %s: %s" % [gs.country_name(ev["receiver"]), "; ".join(ev["reasons"])], 12, UiTheme.TEXT_DIM)
	var hb2 := HBoxContainer.new()
	hb2.add_child(UiTheme.button("Enviar propuesta", func():
		var res := VPeaceSystem.propose(gs, w, me, mode, goals)
		_msg.text = "¡Paz firmada!" if res.get("accepted", false) else "Rechazada."
		changed.emit()
		rebuild()))
	hb2.add_child(UiTheme.button("Proponer paz blanca", func():
		var res2 := VPeaceSystem.propose(gs, w, me, "demand", [])
		_msg.text = "¡Paz blanca firmada!" if res2.get("accepted", false) else "Rechazada."
		changed.emit()
		rebuild()))
	_content.add_child(hb2)
