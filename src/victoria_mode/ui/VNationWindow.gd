class_name VNationWindow
extends PanelContainer
## Ventana nacional con pestañas (Producción, Presupuesto, Tecnología, Política,
## Población, Comercio, Diplomacia, Militar, Alertas). Cada pestaña lee datos reales del estado.
## Las fases posteriores ampliarán cada pestaña (mercado, reformas, árbol tecnológico, CB...).

signal country_focus(tag: String)
signal province_focus(province_id: int)

const TITLES := {
	"production": "Producción", "budget": "Presupuesto", "technology": "Tecnología", "politics": "Política",
	"population": "Población", "trade": "Comercio", "diplomacy": "Diplomacia", "military": "Militar", "alerts": "Alertas",
}

var gs: VGameState
var tab: String = ""
var _title_lbl: Label
var _tab_row: HBoxContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _pop_state_filter: int = 0
var _diplo_selected: String = ""
var _budget_labels := {}


func setup(state: VGameState) -> void:
	gs = state
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -540
	offset_right = 540
	offset_top = -330
	offset_bottom = 350
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var bar := UiTheme.title_bar("", func(): close())
	_title_lbl = bar.get_child(0).get_child(0)
	v.add_child(bar)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	v.add_child(_tab_row)
	for key in ["production", "budget", "technology", "politics", "population", "trade", "diplomacy", "military"]:
		var b := UiTheme.button(TITLES[key], func(): open(key))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("tab", key)
		_tab_row.add_child(b)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	visible = false


func open(key: String) -> void:
	if visible and tab == key and key != "":
		pass
	tab = key
	visible = true
	_title_lbl.text = ("%s — %s" % [TITLES.get(key, key), gs.country_name(gs.player_tag)]).to_upper()
	for b in _tab_row.get_children():
		var on: bool = b.get_meta("tab") == key
		b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.HEADER if on else UiTheme.BUTTON, UiTheme.GOLD if on else UiTheme.GOLD_DIM, 1, 3, 10))
		b.add_theme_color_override("font_color", UiTheme.ACCENT if on else UiTheme.TEXT)
	rebuild()
	_scroll.scroll_vertical = 0


func toggle(key: String) -> void:
	if visible and tab == key:
		close()
	else:
		open(key)


func close() -> void:
	visible = false


## Refresco diario ligero (solo etiquetas del presupuesto).
func refresh_live() -> void:
	if visible and tab == "budget":
		_update_budget_labels()


## Refresco mensual: reconstruye la pestaña (salvo presupuesto, para no interrumpir los sliders).
func refresh_month() -> void:
	if not visible:
		return
	if tab == "budget":
		_update_budget_labels()
		return
	var sv := _scroll.scroll_vertical
	rebuild()
	_scroll.scroll_vertical = sv


func rebuild() -> void:
	for ch in _content.get_children():
		ch.queue_free()
	_budget_labels.clear()
	match tab:
		"production": _build_production()
		"budget": _build_budget()
		"technology": _build_technology()
		"politics": _build_politics()
		"population": _build_population()
		"trade": _build_trade()
		"diplomacy": _build_diplomacy()
		"military": _build_military()
		"alerts": _build_alerts()


# ---------------------------------------------------------------- helpers
func _section(text: String) -> void:
	var l := UiTheme.label(text.to_upper(), 14, UiTheme.GOLD)
	_content.add_child(l)
	_content.add_child(UiTheme.separator())


func _note(text: String) -> void:
	var l := UiTheme.label(text, 13, UiTheme.TEXT_MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)


func _table(headers: Array, rows: Array, widths: Array = []) -> GridContainer:
	var g := GridContainer.new()
	g.columns = headers.size()
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 3)
	for i in headers.size():
		var h := UiTheme.label(str(headers[i]), 12, UiTheme.TEXT_MUTED)
		if i < widths.size() and widths[i] > 0:
			h.custom_minimum_size.x = widths[i]
		if i == 0:
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(h)
	for r in rows:
		for i in r.size():
			var cell = r[i]
			if cell is Control:
				g.add_child(cell)
			else:
				var l := UiTheme.label(str(cell), 13, UiTheme.TEXT)
				if i == 0:
					l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				g.add_child(l)
	_content.add_child(g)
	return g


func _country() -> Dictionary:
	return gs.countries[gs.player_tag]


# ------------------------------------------------------------ producción
var _build_type_opt: OptionButton
var _build_state_opt: OptionButton
var _build_msg: Label


func _msg_label() -> Label:
	var l := UiTheme.label("", 13, UiTheme.ACCENT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_production() -> void:
	var tag := gs.player_tag
	var c := _country()
	var policy := VProductionSystem.economic_policy(gs, tag)
	var open := 0
	var closed := 0
	var levels := 0
	var emp := 0
	var maxw := 0
	var profit := 0.0
	for si in gs.country_state_instances(tag):
		for f in si["factories"]:
			if f["open"]:
				open += 1
			else:
				closed += 1
			levels += int(f["level"])
			emp += int(f["craftsmen_employed"]) + int(f["clerks_employed"])
			maxw += int(f["max_workers"])
			profit += float(f["profit"])
	_section("Industria")
	_table(["Concepto", "Valor"], [
		["Fábricas abiertas / cerradas", "%d / %d (niveles: %d)" % [open, closed, levels]],
		["Empleo industrial", "%s / %s plazas" % [UiTheme.fmt_int(emp), UiTheme.fmt_int(maxw)]],
		["Beneficio total del último mes", "%+.1f" % profit],
		["Política económica del gobierno", _policy_name(policy)],
		["Inversión privada", "Permitida" if policy in gs.economy_rules.get("investment_policies", []) else "No permitida"],
		["Construcción estatal / subvenciones", "%s / %s" % ["Sí" if policy in gs.economy_rules.get("government_build_policies", []) else "No", "Sí" if policy in gs.economy_rules.get("subsidy_policies", []) else "No"]],
	], [320, 360])
	# proyectos
	if not c.get("projects", []).is_empty():
		_section("Proyectos en construcción")
		var prow := []
		for pr in c["projects"]:
			var pb := ProgressBar.new()
			pb.value = float(pr["progress"]) * 100.0
			pb.custom_minimum_size = Vector2(160, 14)
			pb.show_percentage = false
			prow.append([gs.factory_types[pr["type"]]["name"] + (" (ampliación)" if pr["expand"] else ""),
				gs.states[int(str(pr["state_key"]).split(":")[0])]["name"], "Capitalistas" if pr["investor"] == "capitalists" else "Estado", pb])
		_table(["Fábrica", "Estado", "Inversor", "Progreso"], prow, [260, 220, 110, 160])
	# construir (Estado)
	_section("Construir fábrica (Estado)")
	var hb := HBoxContainer.new()
	_build_type_opt = OptionButton.new()
	var types: Array = gs.factory_types.keys()
	types.sort()
	for t in types:
		var ok := VProductionSystem.can_build_type(gs, tag, t)
		_build_type_opt.add_item("%s%s · margen %.0f/mes" % [gs.factory_types[t]["name"], "" if ok else " (requiere tecnología)", VProductionSystem.expected_margin(gs, tag, t)])
		_build_type_opt.set_item_metadata(_build_type_opt.item_count - 1, t)
		_build_type_opt.set_item_disabled(_build_type_opt.item_count - 1, not ok)
	hb.add_child(_build_type_opt)
	_build_state_opt = OptionButton.new()
	for si in gs.country_state_instances(tag).slice(0, 40):
		_build_state_opt.add_item(gs.states[si["state"]]["name"])
		_build_state_opt.set_item_metadata(_build_state_opt.item_count - 1, si["key"])
	hb.add_child(_build_state_opt)
	hb.add_child(UiTheme.button("Construir", _on_build))
	_content.add_child(hb)
	_build_msg = _msg_label()
	_content.add_child(_build_msg)
	# fábricas
	_section("Fábricas por estado")
	var rows := []
	for si in gs.country_state_instances(tag):
		for f in si["factories"]:
			var ft: Dictionary = gs.factory_types.get(f["type"], {})
			var st_btn := UiTheme.button(gs.states[si["state"]]["name"], func(): province_focus.emit(si["provinces"][0]))
			st_btn.flat = true
			st_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			st_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var ins := []
			for g in ft.get("inputs", {}):
				ins.append(gs.good_name(g))
			var outs := []
			for g in ft.get("outputs", {}):
				outs.append(gs.good_name(g))
			var name_l := UiTheme.label("%s n%d" % [ft.get("name", f["type"]), int(f["level"])], 13)
			name_l.tooltip_text = "Insumos: %s\nProduce: %s\nStock: %s\nCaja: %.1f" % [", ".join(ins), ", ".join(outs), _fmt_stock(f["stock"]), float(f["cash"])]
			name_l.mouse_filter = Control.MOUSE_FILTER_PASS
			var state_txt := "Cerrada" if not f["open"] else ("Subvencionada" if f["subsidized"] else ("Pérdidas" if float(f["profit"]) < 0.0 else "Rentable"))
			var actions := HBoxContainer.new()
			var exp_b := UiTheme.button("+", func(): _on_expand(si["key"], f), 26, "Ampliar un nivel (paga el Estado)")
			actions.add_child(exp_b)
			var sub_b := UiTheme.button("S" if not f["subsidized"] else "s", func(): _on_subsidy(f), 26, "Activar/desactivar subvención")
			actions.add_child(sub_b)
			rows.append([st_btn, name_l, "%s/%s" % [UiTheme.fmt_big(f["craftsmen_employed"]), UiTheme.fmt_big(int(f["max_workers"]) * 0.9)],
				UiTheme.fmt_big(f["clerks_employed"]), "%.1f" % float(f["output"]), "%.1f" % float(f["revenue"]), "%.1f" % float(f["expenses"]),
				_colored("%+.1f" % float(f["profit"]), float(f["profit"]) >= 0.0), state_txt, actions])
	_table(["Estado", "Fábrica", "Obreros", "Oficin.", "Prod.", "Ingresos", "Gastos", "Beneficio", "Situación", ""], rows, [170, 190, 80, 55, 50, 65, 60, 70, 95, 60])
	_section("Producción primaria (RGO)")
	var by_good := {}
	for id in gs.owned_provinces(tag):
		var rd: Dictionary = gs.provinces[id].get("rgo_data", {})
		var g: String = rd.get("good", gs.provinces[id]["rgo"])
		var e: Array = by_good.get(g, [0, 0, 0, 0.0, 0.0])
		e[0] += 1
		e[1] += int(rd.get("workers", 0))
		e[2] += int(rd.get("max_workers", 0))
		e[3] += float(rd.get("output", 0.0))
		e[4] += float(rd.get("revenue", 0.0))
		by_good[g] = e
	var keys := by_good.keys()
	keys.sort_custom(func(a, b): return by_good[a][4] > by_good[b][4])
	var grows := []
	for g in keys:
		var e: Array = by_good[g]
		grows.append([gs.good_name(g), str(e[0]), "%s / %s" % [UiTheme.fmt_big(e[1]), UiTheme.fmt_big(e[2])], "%.1f" % e[3], "%.1f" % e[4],
			"%.2f" % VMarketSystem.price(gs, g)])
	_table(["Bien", "Prov.", "Trabajadores / máx.", "Producción/mes", "Ingresos/mes", "Precio"], grows, [200, 50, 170, 110, 110, 70])


func _fmt_stock(stock: Dictionary) -> String:
	var parts := []
	for g in stock:
		parts.append("%s %.1f" % [gs.good_name(g), float(stock[g])])
	return ", ".join(parts) if not parts.is_empty() else "vacío"


func _colored(text: String, good: bool) -> Label:
	return UiTheme.label(text, 13, UiTheme.POSITIVE if good else UiTheme.NEGATIVE)


func _policy_name(p: String) -> String:
	for pos in gs.issues.get("economic_policy", {}).get("positions", []):
		if pos["id"] == p:
			return pos["name"]
	return p


func _on_build() -> void:
	if _build_type_opt.selected < 0 or _build_state_opt.selected < 0:
		return
	var t: String = _build_type_opt.get_item_metadata(_build_type_opt.selected)
	var key: String = _build_state_opt.get_item_metadata(_build_state_opt.selected)
	var err := VProductionSystem.government_build(gs, gs.player_tag, key, t)
	_build_msg.text = err if err != "" else "Proyecto iniciado: %s." % gs.factory_types[t]["name"]
	if err == "":
		rebuild()


func _on_expand(key: String, f: Dictionary) -> void:
	var err := VProductionSystem.government_build(gs, gs.player_tag, key, f["type"], int(f["id"]))
	if _build_msg:
		_build_msg.text = err if err != "" else "Ampliación iniciada."
	if err == "":
		rebuild()


func _on_subsidy(f: Dictionary) -> void:
	var err := VProductionSystem.set_subsidy(gs, gs.player_tag, f, not f["subsidized"])
	if err != "" and _build_msg:
		_build_msg.text = err
	else:
		rebuild()


# ------------------------------------------------------------ presupuesto
func _build_budget() -> void:
	var c := _country()
	var b: Dictionary = c["budget"]
	_section("Ingresos (tipos)")
	_slider("Impuestos a los pobres", "tax_poor", b)
	_slider("Impuestos a la clase media", "tax_middle", b)
	_slider("Impuestos a los ricos", "tax_rich", b)
	_slider("Aranceles (sobre importaciones)", "tariffs", b)
	_section("Gastos (nivel de gasto)")
	_slider("Educación (salario del clero → alfabetización)", "education", b)
	_slider("Administración (burócratas → eficiencia fiscal)", "administration", b)
	_slider("Ejército: salarios de soldados y oficiales", "military", b)
	_slider("Reserva militar (compra de armas y munición)", "stockpile", b)
	_slider("Gasto social (paro, pensiones, sanidad)", "social", b)
	_section("Último mes")
	for k in ["tax_poor", "tax_middle", "tax_rich", "tariffs", "other", "sep", "education", "administration", "military_wages", "stockpile", "social", "subsidies", "construction", "interest", "sep", "income", "expense", "balance", "treasury", "debt", "bank", "efficiency"]:
		if k == "sep":
			_content.add_child(UiTheme.separator())
			continue
		var hb := HBoxContainer.new()
		var nm: String = {"tax_poor": "Impuestos pobres", "tax_middle": "Impuestos clase media", "tax_rich": "Impuestos ricos",
			"tariffs": "Aranceles", "other": "Otros ingresos", "education": "Educación", "administration": "Administración",
			"military_wages": "Salarios militares", "stockpile": "Reserva militar", "social": "Gasto social",
			"subsidies": "Subvenciones", "construction": "Construcción", "interest": "Intereses de la deuda",
			"income": "INGRESOS", "expense": "GASTOS", "balance": "BALANCE MENSUAL", "treasury": "Tesoro",
			"debt": "Deuda (nacional / extranjera)", "bank": "Banco nacional (depósitos / prestado al Estado)",
			"efficiency": "Eficiencia administrativa / fiscal"}[k]
		var l := UiTheme.label(nm, 14, UiTheme.TEXT_DIM)
		l.custom_minimum_size.x = 380
		hb.add_child(l)
		var val := UiTheme.label("", 14, UiTheme.TEXT)
		hb.add_child(val)
		_budget_labels[k] = val
		_content.add_child(hb)
	_note("Los impuestos se cobran sobre la renta real de los POPs al recibirla. Los aranceles encarecen la parte importada de cada bien para compradores y fábricas. Si el tesoro queda en negativo, el Estado se endeuda (primero con el banco nacional, después con prestamistas extranjeros a mayor interés). Los cambios se notan al cierre del mes.")
	_update_budget_labels()


func _slider(text: String, key: String, b: Dictionary) -> void:
	var hb := HBoxContainer.new()
	var l := UiTheme.label(text, 14)
	l.custom_minimum_size.x = 380
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.value = float(b.get(key, 0.0)) * 100.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 22
	var val := UiTheme.label("%d%%" % int(s.value), 14, UiTheme.ACCENT)
	val.custom_minimum_size.x = 50
	s.value_changed.connect(func(x):
		b[key] = x / 100.0
		val.text = "%d%%" % int(x))
	hb.add_child(s)
	hb.add_child(val)
	_content.add_child(hb)


func _update_budget_labels() -> void:
	if _budget_labels.is_empty():
		return
	var c := _country()
	var last: Dictionary = c.get("budget_last", {})
	for k in VBudgetSystem.INCOME_KEYS + VBudgetSystem.EXPENSE_KEYS:
		if _budget_labels.has(k):
			_budget_labels[k].text = "%.1f" % float(last.get(k, 0.0))
	var inc := float(c.get("monthly_income", 0.0))
	var expense := float(c.get("monthly_expense", 0.0))
	_budget_labels["income"].text = "%+.1f" % inc
	_budget_labels["expense"].text = "%.1f" % expense
	_budget_labels["balance"].text = "%+.1f" % (inc - expense)
	_budget_labels["balance"].add_theme_color_override("font_color", UiTheme.POSITIVE if inc >= expense else UiTheme.NEGATIVE)
	_budget_labels["treasury"].text = UiTheme.fmt_money(float(c["treasury"]))
	var debt := float(c.get("debt", 0.0))
	var foreign := float(c.get("debt_foreign", 0.0))
	_budget_labels["debt"].text = "%s  (%s / %s)" % [UiTheme.fmt_money(debt), UiTheme.fmt_money(debt - foreign), UiTheme.fmt_money(foreign)]
	_budget_labels["debt"].add_theme_color_override("font_color", UiTheme.NEGATIVE if debt > 0.0 else UiTheme.TEXT)
	var bank: Dictionary = c.get("bank", {})
	_budget_labels["bank"].text = "%s / %s" % [UiTheme.fmt_money(float(bank.get("deposits", 0.0))), UiTheme.fmt_money(float(bank.get("lent", 0.0)))]
	_budget_labels["efficiency"].text = "%.0f%% / %.0f%%%s" % [float(c.get("admin_efficiency", 0.0)) * 100.0, float(c.get("tax_efficiency", 0.0)) * 100.0,
		"  · ¡salarios recortados por deuda!" if float(c.get("pay_ratio", 1.0)) < 1.0 else ""]


# ------------------------------------------------------------ tecnología
func _build_technology() -> void:
	var tag := gs.player_tag
	var c := _country()
	_section("Investigación")
	var cur: String = c.get("research", "")
	var rows := [["Puntos de investigación / mes", "%.1f" % float(c.get("research_points_monthly", 0.0))],
		["Investigando", gs.technologies.get(cur, {}).get("name", "Nada (elige una tecnología disponible)")]]
	_table(["Concepto", "Valor"], rows, [320, 400])
	if cur != "":
		var pb := ProgressBar.new()
		pb.max_value = float(gs.technologies[cur]["cost"])
		pb.value = float(c.get("research_progress", 0.0))
		pb.custom_minimum_size = Vector2(0, 18)
		_content.add_child(pb)
		var rpm := maxf(0.01, float(c.get("research_points_monthly", 0.0)))
		_note("%.0f / %.0f puntos · unos %d meses restantes" % [float(c.get("research_progress", 0.0)), float(gs.technologies[cur]["cost"]), int(ceil((float(gs.technologies[cur]["cost"]) - float(c.get("research_progress", 0.0))) / rpm))])
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	_content.add_child(grid)
	for cat in gs.tech_categories:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiTheme.label(cat["name"].to_upper(), 14, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		var techs := []
		for t in gs.technologies:
			if gs.technologies[t]["category"] == cat["id"]:
				techs.append(t)
		techs.sort_custom(func(a, b): return int(gs.technologies[a]["tier"]) < int(gs.technologies[b]["tier"]))
		for t in techs:
			var td: Dictionary = gs.technologies[t]
			var done: bool = t in c["technologies"]
			var avail := VTechnologySystem.can_research(gs, tag, t)
			var b := Button.new()
			b.text = td["name"]
			b.clip_text = true
			b.custom_minimum_size = Vector2(0, 30)
			var unl := ""
			if not td.get("unlocks_factories", []).is_empty():
				var names := []
				for f in td["unlocks_factories"]:
					names.append(gs.factory_types.get(f, {}).get("name", f))
				unl = "\nDesbloquea: " + ", ".join(names)
			var pre := []
			for p in td.get("prerequisites", []):
				pre.append(gs.technologies.get(p, {}).get("name", p))
			b.tooltip_text = "%s (nivel %d)\nCoste: %d puntos\nEfectos: %s%s%s" % [td["name"], int(td["tier"]), int(td["cost"]), VModifiers.describe(td.get("effects", {})), unl,
				("\nRequiere: " + ", ".join(pre)) if not pre.is_empty() else ""]
			if done:
				b.add_theme_stylebox_override("normal", UiTheme.box(Color("2d4a2a"), UiTheme.GOLD_DIM, 1, 3, 6))
				b.disabled = false
			elif t == cur:
				b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.SELECTED, UiTheme.ACCENT, 2, 3, 6))
			elif not avail:
				b.disabled = true
			b.pressed.connect(func():
				if VTechnologySystem.set_research(gs, tag, t):
					rebuild())
			col.add_child(b)
		grid.add_child(col)
	_section("Inventos")
	var irows := []
	for i in gs.inventions:
		var inv: Dictionary = gs.inventions[i]
		var state: String = "Activado" if i in c.get("inventions", []) else ("Posible (%.0f%%/mes)" % (float(inv["chance"]) * (1.0 + float(c.get("literacy", 0.0))) * 100.0) if inv["technology"] in c["technologies"] else "Requiere " + gs.technologies.get(inv["technology"], {}).get("name", ""))
		irows.append([inv["name"], VModifiers.describe(inv.get("effects", {})), state])
	_table(["Invento", "Efectos", "Estado"], irows, [240, 340, 220])
	_note("Magia: %s. Al activarse GLOBAL_MAGIC_ACTIVATED cada nación recibirá ramas arcanas según sus datos (magic_branches)." % ("desbloqueada" if gs.flags.get("magic_unlocked", false) else "aún no desbloqueada (magic_unlocked = false)"))


# --------------------------------------------------------------- política
func _build_politics() -> void:
	var tag := gs.player_tag
	var c := _country()
	var gov: Dictionary = gs.governments.get(c["government"], {})
	var rp := VPoliticsSystem.ruling_party(gs, tag)
	_section("Gobierno")
	var months_left := int(c.get("next_election_month", -1)) - gs.month_index
	_table(["Concepto", "Valor"], [
		["Forma de gobierno", gov.get("name", c["government"])],
		["Partido gobernante", "%s (%s)" % [rp.get("name", "—"), gs.ideologies.get(rp.get("ideology", ""), {}).get("name", "")]],
		["Elecciones", ("Sí · próximas en %d meses" % maxi(0, months_left)) if gov.get("elections", false) else "No (el jefe de Estado designa el gobierno)"],
		["Derecho de voto", gs.reforms["voting"]["levels"][gs.reform_level(tag, "voting")]["name"]],
	], [260, 500])
	_msg = _msg_label()
	if gov.get("elections", false):
		_content.add_child(UiTheme.button("Convocar elecciones anticipadas", func():
			VPoliticsSystem.hold_election(gs, tag)
			rebuild()))
	var le: Dictionary = c.get("last_election", {})
	if not le.is_empty():
		var votes: Array = le["votes"]
		var segs := []
		var parties: Array = c["parties"]
		for i in parties.size():
			segs.append([float(votes[i]), gs.ideologies.get(parties[i]["ideology"], {}).get("color_obj", Color.GRAY), parties[i]["name"]])
		_content.add_child(UiTheme.label("Últimas elecciones (%s): gana %s" % [le.get("date", ""), parties[int(le["winner"])]["name"]], 13, UiTheme.TEXT_DIM))
		var bar := VStackBar.create(18)
		bar.set_segments(segs)
		_content.add_child(bar)
	_section("Partidos")
	var prow := []
	var parties2: Array = c["parties"]
	for i in parties2.size():
		var p: Dictionary = parties2[i]
		var pol: Dictionary = p["policies"]
		var can := VPoliticsSystem.party_can_rule(gs, tag, p)
		var act: Control = UiTheme.label("Gobierna" if i == int(c["ruling_party_index"]) else ("Puede gobernar" if can else ("Ilegal" if not VPoliticsSystem.party_available(gs, tag, p) else "Excluido")), 13)
		if gov.get("appoint_ruling_party", false) and can and i != int(c["ruling_party_index"]):
			act = UiTheme.button("Designar", func():
				_msg.text = VPoliticsSystem.appoint_party(gs, tag, i)
				rebuild())
		prow.append([p["name"], gs.ideologies.get(p["ideology"], {}).get("name", ""), _pos_name("economic_policy", pol.get("economic_policy", "")),
			_pos_name("trade", pol.get("trade_policy", "")), _pos_name("religious_policy", pol.get("religious_policy", "")),
			_pos_name("citizenship", pol.get("citizenship_policy", "")), _pos_name("military_policy", pol.get("war_policy", "")), act])
	_table(["Partido", "Ideología", "Economía", "Comercio", "Religión", "Ciudadanía", "Guerra", ""], prow, [220, 90, 120, 95, 85, 110, 85, 90])
	_content.add_child(_msg)
	_section("Cámara alta")
	var uh: Dictionary = c.get("upper_house", {})
	var useg := []
	for k in uh:
		useg.append([float(uh[k]), gs.ideologies.get(k, {}).get("color_obj", Color.GRAY), gs.ideologies.get(k, {}).get("name", k)])
	var ub := VStackBar.create(18)
	ub.set_segments(useg)
	_content.add_child(ub)
	_section("Reformas")
	var rrows := []
	for rid in gs.reform_order:
		var r: Dictionary = gs.reforms[rid]
		var lvl := gs.reform_level(tag, rid)
		var levels := []
		for i in r["levels"].size():
			levels.append(("[%s]" if i == lvl else "%s") % r["levels"][i]["name"])
		var down := VPoliticsSystem.can_change_reform(gs, tag, rid, -1)
		var up := VPoliticsSystem.can_change_reform(gs, tag, rid, 1)
		var box := HBoxContainer.new()
		var bd := UiTheme.button("-", func():
			_msg.text = VPoliticsSystem.change_reform(gs, tag, rid, -1)
			rebuild(), 28, "Retroceder un nivel\n" + (("Apoyo %.0f%% · oposición %.0f%%" % [float(down["support"]) * 100.0, float(down["against"]) * 100.0]) if down["ok"] else down["reason"]))
		bd.disabled = not down["ok"]
		var bu := UiTheme.button("+", func():
			_msg.text = VPoliticsSystem.change_reform(gs, tag, rid, 1)
			rebuild(), 28, "Avanzar un nivel\n" + (("Apoyo %.0f%% · oposición %.0f%%" % [float(up["support"]) * 100.0, float(up["against"]) * 100.0]) if up["ok"] else up["reason"]))
		bu.disabled = not up["ok"]
		box.add_child(bd)
		box.add_child(bu)
		rrows.append([r["name"], "Política" if r["type"] == "political" else "Social", " → ".join(levels), box])
	_table(["Reforma", "Tipo", "Niveles (actual entre corchetes)", ""], rrows, [190, 70, 520, 70])
	_section("Movimientos")
	var mrows := []
	var mvs: Dictionary = c.get("movements", {})
	for rid in mvs:
		var mv: Dictionary = mvs[rid]
		if float(mv["support"]) < 0.002 and float(mv["radicalism"]) < 0.01:
			continue
		mrows.append([mv["name"], "%.1f%%" % (float(mv["support"]) * 100.0), "%.0f%%" % (float(mv["organisation"]) * 100.0),
			_colored("%.0f%%" % (float(mv["radicalism"]) * 100.0), float(mv["radicalism"]) < 0.5), "¡Riesgo de rebelión!" if mv.get("rebel_risk", false) else ""])
	if mrows.is_empty():
		_note("No hay movimientos significativos: la población tiene poca conciencia política o sus demandas ya están satisfechas.")
	else:
		_table(["Movimiento", "Apoyo", "Organización", "Radicalismo", ""], mrows, [300, 80, 110, 100, 160])
	_note("Un movimiento reúne a los POPs con conciencia ≥ 1,5 que desean más de una reforma (según sus issues). Si se ignora gana organización y radicalismo, que eleva la militancia de sus partidarios. Conceder la reforma lo desactiva. Las rebeliones armadas llegarán con el milestone militar.")


var _msg: Label


func _pos_name(issue: String, pos: String) -> String:
	for p in gs.issues.get(issue, {}).get("positions", []):
		if p["id"] == pos:
			return p["name"]
	return pos


# -------------------------------------------------------------- población
func _build_population() -> void:
	var tag := gs.player_tag
	var c := _country()
	var instances := gs.country_state_instances(tag)
	var hb := HBoxContainer.new()
	hb.add_child(UiTheme.label("Filtrar por estado: ", 14, UiTheme.TEXT_DIM))
	var ob := OptionButton.new()
	ob.add_item("Toda la nación", 0)
	var idx := 1
	for si in instances:
		ob.add_item(gs.states[si["state"]]["name"], int(si["state"]))
		if int(si["state"]) == _pop_state_filter:
			ob.select(idx)
		idx += 1
	ob.item_selected.connect(func(i):
		_pop_state_filter = ob.get_item_id(i)
		rebuild())
	hb.add_child(ob)
	_content.add_child(hb)
	var ids: Array = gs.owned_provinces(tag) if _pop_state_filter == 0 else gs.state_part(_pop_state_filter, tag)
	var agg := {}
	var total := 0
	var npops := 0
	for id in ids:
		for pop in gs.provinces[id]["pops"]:
			npops += 1
			var s := float(pop["size"])
			total += int(pop["size"])
			var e: Dictionary = agg.get(pop["type"], {"size": 0.0, "n": 0, "lit": 0.0, "mil": 0.0, "con": 0.0, "emp": 0.0, "life": 0.0, "every": 0.0, "lux": 0.0, "income": 0.0, "cash": 0.0})
			e["size"] += s
			e["n"] += 1
			e["lit"] += float(pop["literacy"]) * s
			e["mil"] += float(pop["militancy"]) * s
			e["con"] += float(pop["consciousness"]) * s
			e["emp"] += float(pop["employment"]) * s
			e["life"] += float(pop["needs_satisfaction"]["life"]) * s
			e["every"] += float(pop["needs_satisfaction"]["everyday"]) * s
			e["lux"] += float(pop["needs_satisfaction"]["luxury"]) * s
			e["income"] += float(pop["income"])
			e["cash"] += float(pop["cash"])
			agg[pop["type"]] = e
	var mob: Dictionary = c.get("acc_mobility_last", {})
	_section("Resumen  ·  %s personas en %d POPs" % [UiTheme.fmt_int(total), npops])
	_table(["Último mes", "Personas"], [
		["Promocionados (a un estrato superior)", UiTheme.fmt_int(mob.get("promoted", 0))],
		["Democionados (a un estrato inferior)", UiTheme.fmt_int(mob.get("demoted", 0))],
		["Cambio de oficio (mismo estrato)", UiTheme.fmt_int(mob.get("changed_job", 0))],
		["Migración interna", UiTheme.fmt_int(mob.get("migrated", 0))],
		["Emigrantes / inmigrantes", "%s / %s" % [UiTheme.fmt_int(mob.get("emigrated", 0)), UiTheme.fmt_int(mob.get("immigrated", 0))]],
		["Desempleo medio", "%.1f%%" % (float(c.get("unemployment", 0.0)) * 100.0)],
	], [360, 160])
	_section("POPs por tipo")
	var rows := []
	var keys := agg.keys()
	keys.sort_custom(func(a, b): return agg[a]["size"] > agg[b]["size"])
	for k in keys:
		var e: Dictionary = agg[k]
		var n := maxf(1.0, float(e["size"]))
		var sw := ColorRect.new()
		sw.color = gs.pop_types.get(k, {}).get("color_obj", Color.GRAY)
		sw.custom_minimum_size = Vector2(12, 12)
		var nb := HBoxContainer.new()
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(sw)
		var nl := UiTheme.label(gs.pop_type_name(k), 13)
		nl.tooltip_text = _needs_tooltip(k)
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		nb.add_child(nl)
		rows.append([nb, UiTheme.fmt_big(e["size"]), "%.0f%%" % (float(e["size"]) / maxf(1.0, float(total)) * 100.0),
			"%.0f%%" % (e["emp"] / n * 100.0), _need_cell(e["life"] / n), _need_cell(e["every"] / n), _need_cell(e["lux"] / n),
			"%.1f" % (e["income"] / n * 10000.0), "%.0f%%" % (e["lit"] / n * 100.0), "%.2f" % (e["con"] / n), "%.2f" % (e["mil"] / n), str(e["n"])])
	_table(["Tipo", "Tamaño", "%", "Empleo", "Vida", "Diario", "Lujo", "Renta/10k", "Alfab.", "Conc.", "Milit.", "POPs"], rows, [170, 70, 40, 60, 50, 50, 50, 75, 55, 50, 50, 45])
	_note("Pasa el ratón sobre un tipo para ver su cesta de necesidades. Vida/Diario/Lujo = fracción satisfecha el último mes.")
	_section("Ideología")
	var mix := VPopulationSystem.ideology_mix(gs, ids)
	var bar := VStackBar.create(18)
	var segs := []
	for k in mix:
		segs.append([mix[k], gs.ideologies.get(k, {}).get("color_obj", Color.GRAY), gs.ideologies.get(k, {}).get("name", k)])
	bar.set_segments(segs)
	_content.add_child(bar)
	_section("Issues (posición mayoritaria)")
	var iss := {}
	for id in ids:
		for pop in gs.provinces[id]["pops"]:
			for k in pop.get("issues", {}):
				var d: Dictionary = iss.get(k, {})
				d[pop["issues"][k]] = float(d.get(pop["issues"][k], 0.0)) + float(pop["size"])
				iss[k] = d
	var irows := []
	for k in iss:
		var d: Dictionary = iss[k]
		var best := ""
		var bv := 0.0
		var tot := 0.0
		for pos in d:
			tot += float(d[pos])
			if float(d[pos]) > bv:
				bv = float(d[pos])
				best = pos
		irows.append([gs.issues.get(k, {}).get("name", k), _pos_name(k, best), "%.0f%%" % (bv / maxf(1.0, tot) * 100.0)])
	_table(["Cuestión", "Posición mayoritaria", "Apoyo"], irows, [220, 240, 80])
	_section("Culturas")
	_shares_table(VPopulationSystem.sizes_by(gs, ids, "culture"), func(k): return gs.culture_name(k))
	_section("Religiones")
	_shares_table(VPopulationSystem.sizes_by(gs, ids, "religion"), func(k): return gs.religion_name(k))


func _need_cell(v: float) -> Label:
	var col := UiTheme.POSITIVE if v >= 0.8 else (UiTheme.TEXT if v >= 0.4 else UiTheme.NEGATIVE)
	return UiTheme.label("%.0f%%" % (v * 100.0), 13, col)


func _needs_tooltip(type_id: String) -> String:
	var lines := []
	for tier in VPopulationSystem.TIERS:
		var b := VPopulationSystem.needs_basket(gs, type_id, tier)
		var parts := []
		for g in b:
			parts.append("%s %.2f" % [gs.good_name(g), float(b[g])])
		lines.append("%s: %s" % [{"life": "Vida", "everyday": "Diario", "luxury": "Lujo"}[tier], ", ".join(parts)])
	return "Necesidades por 10.000 personas/mes\n" + "\n".join(lines)


func _shares_table(d: Dictionary, namer: Callable) -> void:
	var total := 0
	for k in d:
		total += int(d[k])
	var keys := d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var rows := []
	for k in keys:
		rows.append([namer.call(k), UiTheme.fmt_int(d[k]), "%.1f%%" % (float(d[k]) / maxf(1.0, float(total)) * 100.0)])
	_table(["Nombre", "Población", "%"], rows, [260, 120, 70])


# --------------------------------------------------------------- comercio
func _build_trade() -> void:
	var tag := gs.player_tag
	_section("Mercado (mes anterior)")
	_note("Orden de compra: mercado interno → esfera de influencia → mercado mundial (las potencias mejor clasificadas importan primero). Precio mundial dinámico según oferta y demanda, entre 0,25× y 4× el precio base. Arancel actual: %.0f%%." % (float(_country()["budget"].get("tariffs", 0.0)) * 100.0))
	var cats := {"raw": "Materia prima", "industrial": "Industrial", "consumer": "Consumo", "luxury": "Lujo", "military": "Militar", "fantasy": "Fantástico"}
	var w: Dictionary = gs.market.get("world", {})
	var rows := []
	var goods: Array = gs.goods.keys()
	goods.sort_custom(func(a, b): return [gs.goods[a]["category"], a] < [gs.goods[b]["category"], b])
	for g in goods:
		var gd: Dictionary = gs.goods[g]
		if not VMarketSystem.is_available(gs, g):
			continue
		var cg := VMarketSystem.country_good(gs, tag, g)
		var p := VMarketSystem.price(gs, g)
		var base := float(gd["base_price"])
		var sw := ColorRect.new()
		sw.color = gd["color_obj"]
		sw.custom_minimum_size = Vector2(12, 12)
		var nb := HBoxContainer.new()
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(sw)
		nb.add_child(UiTheme.label(gd["name"], 13))
		var hist: Array = gs.market["history"].get(g, [])
		rows.append([nb, cats.get(gd["category"], gd["category"]), _colored("%.2f" % p, p >= base), VSparkline.create(hist, base),
			UiTheme.fmt_big(float(w.get("supply", {}).get(g, 0.0))), UiTheme.fmt_big(float(w.get("demand", {}).get(g, 0.0))),
			"%.1f" % cg["supply"], "%.1f" % cg["demand"], "%.1f" % cg["imports"], "%.1f" % cg["exports"],
			"%.0f%%" % (VMarketSystem.fill_buy(gs, tag, g) * 100.0)])
	_table(["Bien", "Categoría", "Precio", "Historial", "Oferta mund.", "Demanda mund.", "Oferta nac.", "Demanda nac.", "Import.", "Export.", "Abastec."], rows, [150, 90, 50, 90, 80, 85, 75, 80, 60, 60, 60])
	_note("Abastecimiento = fracción de la demanda nacional atendida. La escasez reduce la satisfacción de necesidades y la producción de las fábricas.")


func _build_alerts() -> void:
	var c := _country()
	_section("Alertas")
	var any := false
	for wid in c["wars"]:
		var w: Dictionary = gs.wars.get(int(wid), {})
		if w.is_empty():
			continue
		_note("En guerra: %s · warscore %+.0f%s" % [w["name"], VWarSystem.warscore_for(w, gs.player_tag), " · ¡oferta de paz pendiente!" if not w.get("offer", {}).is_empty() else ""])
		any = true
	if float(c.get("monthly_balance", 0.0)) < 0.0:
		_note("El presupuesto tiene balance mensual negativo.")
		any = true
	if float(c.get("debt", 0.0)) > 0.0:
		_note("Deuda: %s." % UiTheme.fmt_money(float(c["debt"])))
		any = true
	if c.get("research", "") == "":
		_note("No se está investigando ninguna tecnología.")
		any = true
	for rid in c.get("movements", {}):
		if c["movements"][rid].get("rebel_risk", false):
			_note("Movimiento radicalizado: %s." % c["movements"][rid]["name"])
			any = true
	if not any:
		_note("Sin alertas.")
	_section("Acontecimientos recientes")
	var n := 0
	for i in range(gs.log_entries.size() - 1, -1, -1):
		var e: Dictionary = gs.log_entries[i]
		if e["tag"] != gs.player_tag:
			continue
		_note("%s — %s" % [e["date"], e["text"]])
		n += 1
		if n >= 40:
			break
	if n == 0:
		_note("Todavía no ha ocurrido nada destacable.")
	_section("Rendimiento de la simulación")
	_note(VProfiler.report(gs))


# ------------------------------------------------------------- diplomacia
signal war_open(war_id: int)
signal army_focus(army_id: int)


func _action_button(text: String, chk: Dictionary, cb: Callable, extra_tip: String = "") -> Button:
	var tip := ""
	if chk.get("ok", false):
		tip = "Coste: %.1f" % float(chk.get("cost", 0.0))
		if not chk.get("reasons", []).is_empty():
			tip += "\nIA: %s" % "; ".join(chk["reasons"])
	else:
		tip = chk.get("reason", "")
	if extra_tip != "":
		tip += "\n" + extra_tip
	var b := UiTheme.button(text, cb, 0, tip)
	b.disabled = not chk.get("ok", false)
	b.add_theme_font_size_override("font_size", 12)
	return b


func _build_diplomacy() -> void:
	var me := gs.player_tag
	var mc := _country()
	var is_gp := VInfluenceSystem.is_gp(gs, me)
	_section("Diplomacia — puntos diplomáticos %.1f · infamia %.1f / %.0f%s" % [float(mc.get("diplo_points", 0.0)), float(mc.get("infamy", 0.0)),
		float(gs.war_rules.get("max_infamy", 25.0)), " · Gran Potencia" if is_gp else ""])
	if _diplo_selected == "" or _diplo_selected == me or not gs.countries.has(_diplo_selected):
		var neigh := VDiplomacySystem.neighbor_countries(gs, me)
		_diplo_selected = neigh[0] if not neigh.is_empty() else ""
	if _diplo_selected != "":
		_build_diplo_target(_diplo_selected)
	# guerras, CB y justificaciones
	_section("Guerras")
	if mc["wars"].is_empty():
		_note("En paz.")
	for wid in mc["wars"]:
		var w: Dictionary = gs.wars.get(int(wid), {})
		if w.is_empty():
			continue
		var hb := HBoxContainer.new()
		hb.add_child(UiTheme.label("%s · warscore %+.0f%s" % [w["name"], VWarSystem.warscore_for(w, me), " · ¡oferta de paz!" if not w.get("offer", {}).is_empty() else ""], 14))
		hb.add_child(UiTheme.button("Abrir guerra / paz", func(): war_open.emit(int(wid))))
		_content.add_child(hb)
	_section("Casus belli y justificaciones")
	for j in gs.justifications:
		if j["owner"] != me:
			continue
		var pb := ProgressBar.new()
		pb.value = float(j["progress"]) * 100.0
		pb.custom_minimum_size = Vector2(200, 14)
		var hb2 := HBoxContainer.new()
		hb2.add_child(UiTheme.label("Justificando %s contra %s%s " % [gs.cb_types.get(j["type"], {}).get("name", j["type"]), gs.country_name(j["target"]),
			(": " + gs.states.get(int(j["state_id"]), {}).get("name", "")) if int(j["state_id"]) > 0 else ""], 13))
		hb2.add_child(pb)
		hb2.add_child(UiTheme.label(" ¡DESCUBIERTA!" if j["discovered"] else " (secreta)", 12, UiTheme.NEGATIVE if j["discovered"] else UiTheme.TEXT_DIM))
		hb2.add_child(UiTheme.button("Cancelar", func():
			VCasusBelliSystem.cancel_justification(gs, me)
			rebuild()))
		_content.add_child(hb2)
	var cbs := VCasusBelliSystem.cbs_of(gs, me)
	if cbs.is_empty():
		_note("No tienes casus belli. Justifica uno sobre una nación (selecciónala en la tabla).")
	for cb in cbs:
		var hb3 := HBoxContainer.new()
		hb3.add_child(UiTheme.label("%s contra %s%s · caduca en %d meses " % [gs.cb_types.get(cb["type"], {}).get("name", cb["type"]), gs.country_name(cb["target"]),
			(": " + gs.states.get(int(cb["state_id"]), {}).get("name", "")) if int(cb["state_id"]) > 0 else "", int(cb["expires"]) - gs.month_index], 13))
		var why := VWarSystem.can_declare(gs, me, cb)
		var b := UiTheme.button("Declarar la guerra", func():
			var res := VWarSystem.declare_war(gs, me, cb)
			if res.has("war"):
				war_open.emit(int(res["war"]["id"]))
			rebuild(), 0, why if why != "" else "Usa este casus belli para declarar la guerra (se llamará a los aliados).")
		b.disabled = why != ""
		hb3.add_child(b)
		_content.add_child(hb3)
	# tabla de naciones
	_section("Naciones")
	var rows := []
	for tag in VRankingSystem.ranked(gs):
		if tag == me:
			continue
		var c: Dictionary = gs.countries[tag]
		var nb := HBoxContainer.new()
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(VFlagView.create(c["flag"], Vector2(22, 15)))
		var bn := UiTheme.button(c["name"], func():
			_diplo_selected = tag
			country_focus.emit(tag)
			rebuild())
		bn.flat = true
		bn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bn.add_theme_font_size_override("font_size", 12)
		if tag == _diplo_selected:
			bn.add_theme_color_override("font_color", UiTheme.ACCENT)
		nb.add_child(bn)
		var flags := []
		if VDiplomacySystem.are_allied(gs, me, tag):
			flags.append("Aliado")
		if VDiplomacySystem.has_access(gs, me, tag):
			flags.append("Acceso")
		if tag in mc.get("guarantees", []):
			flags.append("Garantía")
		if VWarSystem.at_war_with(gs, me, tag):
			flags.append("GUERRA")
		if VDiplomacySystem.in_truce(gs, me, tag):
			flags.append("Tregua")
		var leader: String = c.get("sphere_leader", "")
		var op := "—"
		var inf := "—"
		if is_gp and VInfluenceSystem.valid_target(gs, me, tag):
			op = VInfluenceSystem.opinion_name(gs, VInfluenceSystem.opinion(gs, me, tag))
			var e: Dictionary = mc.get("influence", {}).get(tag, {})
			inf = "%.0f" % float(e.get("points", 0.0)) if not e.is_empty() else "0"
		rows.append([nb, str(c["rank"]), VRankingSystem.status_name(c["status"]).replace("Nación ", ""), "%+d" % gs.relation(me, tag), ", ".join(flags),
			VMapLabels.short_name(gs.country_name(leader)) if leader != "" else "—", op, inf])
	_table(["Nación", "Rk", "Rango", "Rel.", "Vínculos", "Esfera", "Opinión", "Influencia"], rows, [240, 30, 120, 50, 140, 90, 90, 70])


func _build_diplo_target(t: String) -> void:
	var me := gs.player_tag
	var c: Dictionary = gs.countries[t]
	_section("Nación seleccionada: %s" % c["name"])
	var info := "Relaciones %+d · %s · ranking %d" % [gs.relation(me, t), VRankingSystem.status_name(c["status"]), int(c["rank"])]
	if VDiplomacySystem.in_truce(gs, me, t):
		info += " · tregua %d meses" % (VDiplomacySystem.truce_with(gs, me, t) - gs.month_index)
	var leader: String = c.get("sphere_leader", "")
	if leader != "":
		info += " · en la esfera de %s" % gs.country_name(leader)
	_note(info)
	var flow := HFlowContainer.new()
	for action in VDiplomacySystem.ACTION_NAMES:
		var chk := VDiplomacySystem.check(gs, me, action, t)
		flow.add_child(_action_button(VDiplomacySystem.ACTION_NAMES[action], chk, func():
			var err := VDiplomacySystem.perform(gs, me, action, t)
			if err != "":
				_note(err)
			rebuild()))
	_content.add_child(flow)
	# influencia
	if VInfluenceSystem.is_gp(gs, me) and VInfluenceSystem.valid_target(gs, me, t):
		var e := VInfluenceSystem.entry(gs, me, t)
		_note("Influencia sobre %s: %.0f puntos · opinión %s · prioridad %d%s" % [VMapLabels.short_name(c["name"]), float(e["points"]),
			VInfluenceSystem.opinion_name(gs, VInfluenceSystem.opinion(gs, me, t)), int(e["priority"]),
			(" · embajada prohibida %d meses" % (int(e["banned_until"]) - gs.month_index)) if int(e["banned_until"]) > gs.month_index else ""])
		var pri := HBoxContainer.new()
		pri.add_child(UiTheme.label("Prioridad: ", 13, UiTheme.TEXT_DIM))
		for p in 4:
			var bp := UiTheme.button(str(p), func():
				var err2 := VInfluenceSystem.set_priority(gs, me, t, p)
				if err2 != "":
					_note(err2)
				rebuild(), 30, "Reparto de la influencia mensual (0 = sin influencia)")
			bp.disabled = int(e["priority"]) == p
			pri.add_child(bp)
		_content.add_child(pri)
		var flow2 := HFlowContainer.new()
		for action in ["increase_opinion", "add_to_sphere", "remove_from_sphere"]:
			var chk2 := VInfluenceSystem.check(gs, me, action, t)
			flow2.add_child(_action_button(VInfluenceSystem.ACTION_NAMES[action], chk2, func():
				var err3 := VInfluenceSystem.perform(gs, me, action, t)
				if err3 != "":
					_note(err3)
				rebuild()))
		for comp in VInfluenceSystem.competitors(gs, t):
			if comp["gp"] == me:
				continue
			for action in ["decrease_opinion", "discredit", "expel_advisors", "ban_embassy"]:
				var chk3 := VInfluenceSystem.check(gs, me, action, t, comp["gp"])
				flow2.add_child(_action_button("%s (%s)" % [VInfluenceSystem.ACTION_NAMES[action], VMapLabels.short_name(gs.country_name(comp["gp"]))], chk3, func():
					var err4 := VInfluenceSystem.perform(gs, me, action, t, comp["gp"])
					if err4 != "":
						_note(err4)
					rebuild()))
		_content.add_child(flow2)
	var comps := VInfluenceSystem.competitors(gs, t)
	if not comps.is_empty():
		var lines := []
		for comp in comps:
			lines.append("%s: opinión %s, %.0f puntos" % [gs.country_name(comp["gp"]), VInfluenceSystem.opinion_name(gs, int(comp["opinion"])), float(comp["points"])])
		_note("Potencias que influyen sobre %s: %s" % [VMapLabels.short_name(c["name"]), " · ".join(lines)])
	# justificar guerra
	var flow3 := HFlowContainer.new()
	for cb_id in gs.cb_types:
		var d: Dictionary = gs.cb_types[cb_id]
		if int(d.get("justify_months", 0)) <= 0:
			continue
		var states := [0]
		if d.get("scope", "") == "state":
			states = VCasusBelliSystem.bordering_states(gs, me, t).slice(0, 4)
			if states.is_empty():
				states = [0]
		for sid in states:
			var why := VCasusBelliSystem.can_justify(gs, me, t, cb_id, int(sid))
			var label := "Justificar: %s%s" % [d["name"], (" (" + gs.states[int(sid)]["name"] + ")") if int(sid) > 0 else ""]
			var b := UiTheme.button(label, func():
				var err5 := VCasusBelliSystem.start_justification(gs, me, t, cb_id, int(sid))
				if err5 != "":
					_note(err5)
				rebuild(), 0, why if why != "" else "%d meses · infamia %.1f (completa si se descubre)" % [int(d["justify_months"]), float(d["infamy"])])
			b.disabled = why != ""
			b.add_theme_font_size_override("font_size", 12)
			flow3.add_child(b)
	_content.add_child(flow3)


# ---------------------------------------------------------------- militar
var _recruit_type: OptionButton
var _recruit_prov: OptionButton
var _ship_type: OptionButton
var _ship_port: OptionButton
var _mil_msg: Label


func _build_military() -> void:
	var me := gs.player_tag
	var c := _country()
	var types := VPopulationSystem.sizes_by(gs, gs.owned_provinces(me), "type")
	_mil_msg = _msg_label()
	_section("Fuerzas armadas")
	var need := VSupplySystem.country_monthly_need(gs, me)
	var stock_txt := []
	for g in need:
		stock_txt.append("%s %.1f/%.1f" % [gs.good_name(g), float(c["stockpile"].get(g, 0.0)), float(need[g])])
	_table(["Concepto", "Valor"], [
		["Brigadas / barcos", "%d / %d" % [int(c["military"]["brigades"]), int(c["military"]["ships"])]],
		["Soldier POPs (sostienen las brigadas)", UiTheme.fmt_int(types.get("soldiers", 0))],
		["Oficiales → liderazgo", "%s oficiales · %.1f puntos de liderazgo" % [UiTheme.fmt_int(types.get("officers", 0)), float(c.get("leadership", 0.0))]],
		["Reserva militar (existencias / consumo mensual)", ", ".join(stock_txt) if not stock_txt.is_empty() else "—"],
		["Cansancio bélico", "%.1f" % float(c.get("war_exhaustion", 0.0))],
		["Resolvedor de combate", VCombatSystem.resolver().resolver_name()],
	], [320, 520])
	_section("Ejércitos")
	var rows := []
	for a in VArmySystem.country_armies(gs, me):
		var b := UiTheme.button(a["name"], func(): army_focus.emit(int(a["id"])))
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l: Dictionary = gs.leaders.get(int(a.get("leader", 0)), {})
		var st := "Combate" if int(a["battle"]) > 0 else ("Retirada" if a.get("retreating", false) else ("Embarcado" if int(a["embarked"]) > 0 else ("Marcha" if not a["path"].is_empty() else "Detenido")))
		rows.append([b, gs.provinces[int(a["province"])]["name"], str(a["brigades"].size()), UiTheme.fmt_int(VArmySystem.army_strength(gs, a)),
			"%.0f%%" % (VArmySystem.army_organisation(gs, a) * 100.0), "%.0f%%" % (float(a.get("morale", 1.0)) * 100.0),
			"%.0f%%" % (float(a.get("supply", 1.0)) * 100.0), l.get("name", "—"), st])
	_table(["Ejército", "Ubicación", "Brig.", "Hombres", "Org.", "Moral", "Sumin.", "General", "Estado"], rows, [190, 140, 40, 70, 45, 50, 55, 150, 80])
	var hb := HBoxContainer.new()
	hb.add_child(UiTheme.label("Reclutar brigada: ", 13, UiTheme.TEXT_DIM))
	_recruit_type = OptionButton.new()
	for ut in gs.unit_types:
		var req: String = gs.unit_types[ut].get("requires_tech", "")
		_recruit_type.add_item(gs.unit_types[ut]["name"] + ("" if req == "" or req in c.get("technologies", []) else " (requiere tecnología)"))
		_recruit_type.set_item_metadata(_recruit_type.item_count - 1, ut)
	hb.add_child(_recruit_type)
	_recruit_prov = OptionButton.new()
	for id in gs.owned_provinces(me):
		for pop in gs.provinces[id]["pops"]:
			if pop["type"] == "soldiers" and int(pop["size"]) >= (pop.get("brigades", []).size() + 1) * gs.unit_manpower:
				_recruit_prov.add_item("%s (%s soldados)" % [gs.provinces[id]["name"], UiTheme.fmt_int(pop["size"])])
				_recruit_prov.set_item_metadata(_recruit_prov.item_count - 1, id)
				break
	hb.add_child(_recruit_prov)
	hb.add_child(UiTheme.button("Reclutar", func():
		if _recruit_prov.selected < 0:
			_mil_msg.text = "No hay POPs de soldados con hombres libres para nuevas brigadas."
			return
		var res := VArmySystem.recruit(gs, me, int(_recruit_prov.get_item_metadata(_recruit_prov.selected)), _recruit_type.get_item_metadata(_recruit_type.selected))
		_mil_msg.text = res.get("error", "Brigada reclutada.")
		rebuild()))
	_content.add_child(hb)
	_content.add_child(_mil_msg)
	_section("Líderes")
	var lrows := []
	for lid in gs.leaders:
		var l2: Dictionary = gs.leaders[lid]
		if l2["country"] != me:
			continue
		var where := "sin destino"
		if int(l2.get("army", 0)) > 0:
			where = gs.armies.get(int(l2["army"]), {}).get("name", "?")
		elif int(l2.get("fleet", 0)) > 0:
			where = gs.fleets.get(int(l2["fleet"]), {}).get("name", "?")
		lrows.append([VLeaderSystem.describe(gs, l2), "General" if l2["kind"] == "general" else "Almirante", where])
	_table(["Líder", "Tipo", "Destino"], lrows, [480, 90, 200])
	var hb2 := HBoxContainer.new()
	for kind in ["general", "admiral"]:
		var cost := VLeaderSystem.cost(gs, kind)
		var bl := UiTheme.button("Contratar %s (%.0f)" % ["general" if kind == "general" else "almirante", cost], func():
			var l3 := VLeaderSystem.hire(gs, me, kind)
			_mil_msg.text = "" if not l3.is_empty() else "Faltan puntos de liderazgo."
			rebuild(), 0, "Consume puntos de liderazgo generados por los POPs de oficiales")
		bl.disabled = float(c.get("leadership", 0.0)) < cost
		hb2.add_child(bl)
	_content.add_child(hb2)
	_section("Flotas")
	var frows := []
	for f in VNavySystem.country_fleets(gs, me):
		var fb := UiTheme.button(f["name"], func(): army_focus.emit(-int(f["id"])))
		fb.flat = true
		fb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frows.append([fb, gs.provinces[int(f["location"])]["name"], str(f["ships"].size()), "%d/%d" % [VNavySystem.carried_brigades(gs, f), VNavySystem.capacity(gs, f)], f.get("mission", "idle")])
	_table(["Flota", "Ubicación", "Barcos", "Transporte", "Misión"], frows, [220, 180, 60, 80, 90])
	var hb3 := HBoxContainer.new()
	hb3.add_child(UiTheme.label("Construir barco: ", 13, UiTheme.TEXT_DIM))
	_ship_type = OptionButton.new()
	for st in gs.ship_types:
		_ship_type.add_item(gs.ship_types[st]["name"])
		_ship_type.set_item_metadata(_ship_type.item_count - 1, st)
	hb3.add_child(_ship_type)
	_ship_port = OptionButton.new()
	for id in gs.owned_provinces(me):
		if int(gs.provinces[id].get("naval_base", 0)) > 0:
			_ship_port.add_item(gs.provinces[id]["name"])
			_ship_port.set_item_metadata(_ship_port.item_count - 1, id)
	hb3.add_child(_ship_port)
	hb3.add_child(UiTheme.button("Construir", func():
		if _ship_port.selected < 0:
			_mil_msg.text = "No tienes puertos con base naval."
			return
		var err := VNavySystem.build(gs, me, int(_ship_port.get_item_metadata(_ship_port.selected)), _ship_type.get_item_metadata(_ship_type.selected))
		_mil_msg.text = err if err != "" else "Barco en construcción."
		rebuild()))
	_content.add_child(hb3)
	for item in c.get("ship_queue", []):
		_note("En astillero: %s en %s (%d días)" % [gs.ship_types[item["type"]]["name"], gs.provinces[int(item["port"])]["name"], int(item["days"])])
	_section("Guerras")
	if c["wars"].is_empty():
		_note("En paz.")
	for wid in c["wars"]:
		var w: Dictionary = gs.wars.get(int(wid), {})
		if w.is_empty():
			continue
		var sign := 1.0 if VWarSystem.side_of(w, me) == "attackers" else -1.0
		var hb4 := HBoxContainer.new()
		hb4.add_child(UiTheme.label("%s · warscore %+.0f (batallas %+.0f, ocupación %+.0f, bloqueo %+.0f, objetivos %+.0f)" % [w["name"], VWarSystem.warscore_for(w, me),
			float(w["battle_ws"]) * sign, float(w["occupation_ws"]) * sign, float(w["blockade_ws"]) * sign, float(w["ticking_ws"]) * sign], 13))
		hb4.add_child(UiTheme.button("Abrir", func(): war_open.emit(int(wid))))
		_content.add_child(hb4)
	_section("Rebeldes")
	var facs := VRebelSystem.country_factions(gs, me)
	if facs.is_empty():
		_note("No hay facciones rebeldes.")
	for f2 in facs:
		_note("%s — exigen %s · %s · %d provincias controladas · organización %.0f%%" % [gs.rebel_types.get(f2["type"], {}).get("name", f2["type"]),
			gs.reforms.get(f2["movement"], {}).get("name", f2["movement"]), "en armas" if f2["risen"] else "organizándose",
			f2["controlled_provinces"].size(), float(f2["organisation"]) * 100.0])
