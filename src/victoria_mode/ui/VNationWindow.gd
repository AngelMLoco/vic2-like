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


## Refresco periódico (cada día/mes) sin perder el scroll.
func refresh_live() -> void:
	if not visible:
		return
	if tab == "budget":
		_update_budget_labels()
	elif tab in ["diplomacy", "military", "alerts"]:
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
func _build_production() -> void:
	var tag := gs.player_tag
	_section("Estados y fábricas")
	_note("Las fábricas pertenecen al ESTADO. Un estado dividido entre naciones funciona como partes independientes para cada propietario.")
	var rows := []
	for si in gs.country_state_instances(tag):
		var st: Dictionary = gs.states[si["state"]]
		var types := VPopulationSystem.sizes_by(gs, si["provinces"], "type")
		var fac := []
		for f in si["factories"]:
			fac.append("%s n%d" % [gs.factory_types.get(f["type"], {}).get("name", f["type"]), int(f["level"])])
		var infra := 0.0
		for id in si["provinces"]:
			infra += float(gs.provinces[id]["infrastructure"])
		infra /= max(1, si["provinces"].size())
		var st_name: String = st["name"] + (" (parte)" if gs.state_is_split(si["state"]) else "")
		var btn := UiTheme.button(st_name, func(): province_focus.emit(si["provinces"][0]))
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.append([btn, str(si["provinces"].size()), UiTheme.fmt_big(gs.instance_population(si)),
			UiTheme.fmt_big(types.get("craftsmen", 0)), UiTheme.fmt_big(types.get("clerks", 0)), UiTheme.fmt_big(types.get("capitalists", 0)),
			"%.1f" % infra, ", ".join(fac) if not fac.is_empty() else "—"])
	_table(["Estado", "Prov.", "Población", "Obreros", "Oficinistas", "Capitalistas", "Infra.", "Fábricas"], rows, [220, 40, 80, 70, 80, 80, 40, 260])
	_section("Producción primaria (RGO por provincia)")
	var by_good := {}
	for id in gs.owned_provinces(tag):
		var p: Dictionary = gs.provinces[id]
		by_good[p["rgo"]] = by_good.get(p["rgo"], 0) + 1
	var grows := []
	var keys := by_good.keys()
	keys.sort_custom(func(a, b): return by_good[a] > by_good[b])
	for g in keys:
		grows.append([gs.good_name(g), str(by_good[g]), "%.1f" % float(gs.goods.get(g, {}).get("base_price", 0.0))])
	_table(["Bien", "Provincias", "Precio base"], grows, [220, 90, 90])


# ------------------------------------------------------------ presupuesto
func _build_budget() -> void:
	var c := _country()
	var b: Dictionary = c["budget"]
	_section("Ingresos")
	_slider("Impuestos a los pobres", "tax_poor", b)
	_slider("Impuestos a la clase media", "tax_middle", b)
	_slider("Impuestos a los ricos", "tax_rich", b)
	_slider("Aranceles", "tariffs", b)
	_section("Gastos")
	_slider("Educación", "education", b)
	_slider("Administración", "administration", b)
	_slider("Gasto militar (mantenimiento)", "military", b)
	_slider("Reserva militar (stockpile)", "stockpile", b)
	_slider("Gasto social", "social", b)
	_section("Balance")
	for k in ["income", "expense", "balance", "treasury", "debt", "bank"]:
		var hb := HBoxContainer.new()
		var nm: String = {"income": "Ingresos diarios", "expense": "Gastos diarios", "balance": "Balance diario",
			"treasury": "Tesoro", "debt": "Deuda", "bank": "Banco nacional"}[k]
		var l := UiTheme.label(nm, 14, UiTheme.TEXT_DIM)
		l.custom_minimum_size.x = 260
		hb.add_child(l)
		var val := UiTheme.label("", 15, UiTheme.TEXT)
		hb.add_child(val)
		_budget_labels[k] = val
		_content.add_child(hb)
	_note("Los aranceles, la deuda y el banco nacional se activarán con el mercado (fase 6). Los impuestos se calculan por estrato a partir de los POPs reales.")
	_update_budget_labels()


func _slider(text: String, key: String, b: Dictionary) -> void:
	var hb := HBoxContainer.new()
	var l := UiTheme.label(text, 14)
	l.custom_minimum_size.x = 260
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
	var inc := float(c["income_daily"])
	var expense := float(c["expense_daily"])
	_budget_labels["income"].text = "%+.2f" % inc
	_budget_labels["expense"].text = "%.2f" % expense
	_budget_labels["balance"].text = "%+.2f" % (inc - expense)
	_budget_labels["balance"].add_theme_color_override("font_color", UiTheme.POSITIVE if inc >= expense else UiTheme.NEGATIVE)
	_budget_labels["treasury"].text = UiTheme.fmt_money(float(c["treasury"]))
	_budget_labels["debt"].text = UiTheme.fmt_money(0.0)
	_budget_labels["bank"].text = UiTheme.fmt_money(0.0)


# ------------------------------------------------------------ tecnología
func _build_technology() -> void:
	var c := _country()
	_section("Investigación")
	_table(["Concepto", "Valor"], [
		["Puntos acumulados", "%.1f" % float(c.get("research_points", 0.0))],
		["Puntos diarios", "%.2f" % float(c.get("research_points_daily", 0.0))],
		["Origen", "Clero alfabetizado × gasto en educación"],
	], [300, 200])
	_section("Ramas")
	_table(["Rama", "Estado"], [["Ejército", "Árbol en fase 8"], ["Armada", "Árbol en fase 8"], ["Comercio", "Árbol en fase 8"],
		["Cultura", "Árbol en fase 8"], ["Industria", "Árbol en fase 8"]], [300, 200])
	_section("Magia (configuración nacional)")
	var mb: Dictionary = c.get("magic_branches", {})
	var active: bool = gs.flags.get("GLOBAL_MAGIC_ACTIVATED", false)
	_note("La magia se desbloquea con el acontecimiento mundial GLOBAL_MAGIC_ACTIVATED (%s). Cada nación recibe un número de ramas arcanas por área definido en sus datos." % ("ACTIVADO" if active else "aún no ha ocurrido"))
	var rows := []
	for k in mb:
		rows.append([{"technology": "Tecnología", "economy": "Economía", "military": "Militar", "politics": "Política"}.get(k, k), str(mb[k])])
	_table(["Área", "Ramas arcanas"], rows, [300, 120])


# --------------------------------------------------------------- política
func _build_politics() -> void:
	var c := _country()
	var gov: Dictionary = gs.governments.get(c["government"], {})
	_section("Gobierno")
	_table(["Concepto", "Valor"], [
		["Forma de gobierno", gov.get("name", c["government"])],
		["Descripción", gov.get("description", "")],
		["Elecciones", "Sí" if gov.get("elections", false) else "No"],
		["Partido gobernante", "%s (%s)" % [c["ruling_party"]["name"], gs.ideologies.get(c["ruling_party"]["ideology"], {}).get("name", "")]],
	], [260, 500])
	_section("Opinión ideológica de la población")
	var mix := VPopulationSystem.ideology_mix(gs, gs.owned_provinces(gs.player_tag))
	var bar := VStackBar.create(20)
	var segs := []
	for k in mix:
		segs.append([mix[k], gs.ideologies.get(k, {}).get("color_obj", Color.GRAY), gs.ideologies.get(k, {}).get("name", k)])
	bar.set_segments(segs)
	_content.add_child(bar)
	var rows := []
	var keys := mix.keys()
	keys.sort_custom(func(a, b): return mix[a] > mix[b])
	for k in keys:
		rows.append([gs.ideologies.get(k, {}).get("name", k), "%.1f%%" % (float(mix[k]) * 100.0)])
	_table(["Ideología", "Apoyo"], rows, [260, 100])
	_section("Cámara alta (aproximación por POPs ricos)")
	var rich_ids := gs.owned_provinces(gs.player_tag)
	var upper := {}
	var total := 0.0
	for id in rich_ids:
		for pop in gs.provinces[id]["pops"]:
			if gs.pop_types.get(pop["type"], {}).get("strata", "") != "rich":
				continue
			for k in pop["ideology"]:
				upper[k] = upper.get(k, 0.0) + float(pop["ideology"][k]) * float(pop["size"])
				total += float(pop["ideology"][k]) * float(pop["size"])
	var urows := []
	for k in upper:
		urows.append([gs.ideologies.get(k, {}).get("name", k), "%.1f%%" % (float(upper[k]) / max(1.0, total) * 100.0)])
	_table(["Ideología", "Escaños"], urows, [260, 100])
	_section("Reformas")
	_note("Reformas políticas y sociales, elecciones, issues y movimientos rebeldes llegan con la fase 7 (datos en data/victoria_mode/reforms).")


# -------------------------------------------------------------- población
func _build_population() -> void:
	var tag := gs.player_tag
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
	var types := VPopulationSystem.sizes_by(gs, ids, "type")
	var total := 0
	for k in types:
		total += int(types[k])
	_section("POPs por tipo  ·  total %s" % UiTheme.fmt_int(total))
	var rows := []
	var keys := types.keys()
	keys.sort_custom(func(a, b): return types[a] > types[b])
	for k in keys:
		var sub := []
		for id in ids:
			for pop in gs.provinces[id]["pops"]:
				if pop["type"] == k:
					sub.append(pop)
		var lit := 0.0
		var mil := 0.0
		var con := 0.0
		var n := 0.0
		for pop in sub:
			var s := float(pop["size"])
			n += s
			lit += float(pop["literacy"]) * s
			mil += float(pop["militancy"]) * s
			con += float(pop["consciousness"]) * s
		n = max(n, 1.0)
		var sw := ColorRect.new()
		sw.color = gs.pop_types.get(k, {}).get("color_obj", Color.GRAY)
		sw.custom_minimum_size = Vector2(14, 14)
		var name_box := HBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_child(sw)
		name_box.add_child(UiTheme.label(gs.pop_type_name(k), 13))
		rows.append([name_box, gs.pop_types.get(k, {}).get("strata", ""), UiTheme.fmt_int(types[k]), "%.1f%%" % (float(types[k]) / max(1, total) * 100.0),
			"%.1f%%" % (lit / n * 100.0), "%.2f" % (mil / n), "%.2f" % (con / n), str(sub.size())])
	_table(["Tipo", "Estrato", "Tamaño", "%", "Alfab.", "Milit.", "Conc.", "POPs"], rows, [220, 70, 100, 60, 70, 60, 60, 50])
	_section("Culturas")
	_shares_table(VPopulationSystem.sizes_by(gs, ids, "culture"), func(k): return gs.culture_name(k))
	_section("Religiones")
	_shares_table(VPopulationSystem.sizes_by(gs, ids, "religion"), func(k): return gs.religion_name(k))


func _shares_table(d: Dictionary, namer: Callable) -> void:
	var total := 0
	for k in d:
		total += int(d[k])
	var keys := d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var rows := []
	for k in keys:
		rows.append([namer.call(k), UiTheme.fmt_int(d[k]), "%.1f%%" % (float(d[k]) / max(1, total) * 100.0)])
	_table(["Nombre", "Población", "%"], rows, [260, 120, 70])


# --------------------------------------------------------------- comercio
func _build_trade() -> void:
	_section("Catálogo de bienes")
	_note("Mercado interno → mercado de esfera → mercado mundial, con oferta/demanda y precios dinámicos: fase 6. Aquí se muestra el catálogo y la base productiva mundial actual (RGOs).")
	var world := {}
	for id in range(1, gs.first_sea_id):
		var g: String = gs.provinces[id]["rgo"]
		world[g] = world.get(g, 0) + 1
	var cats := {"raw": "Materia prima", "industrial": "Industrial", "consumer": "Consumo", "luxury": "Lujo", "military": "Militar", "fantasy": "Fantástico (bloqueado)"}
	var rows := []
	for gid in gs.goods:
		var g: Dictionary = gs.goods[gid]
		var sw := ColorRect.new()
		sw.color = g["color_obj"]
		sw.custom_minimum_size = Vector2(14, 14)
		var nb := HBoxContainer.new()
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(sw)
		nb.add_child(UiTheme.label(g["name"], 13))
		rows.append([nb, cats.get(g["category"], g["category"]), "%.2f" % float(g["base_price"]), str(world.get(gid, 0)) if g.get("rgo") != null else "—"])
	_table(["Bien", "Categoría", "Precio base", "Provincias RGO (mundo)"], rows, [240, 180, 100, 160])


# ------------------------------------------------------------- diplomacia
func _build_diplomacy() -> void:
	var me := _country()
	_section("Naciones del mundo")
	var rows := []
	for tag in VRankingSystem.ranked(gs):
		var c: Dictionary = gs.countries[tag]
		var nb := HBoxContainer.new()
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(VFlagView.create(c["flag"], Vector2(24, 16)))
		var b := UiTheme.button(c["name"], func():
			_diplo_selected = tag
			country_focus.emit(tag)
			rebuild())
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if tag == _diplo_selected:
			b.add_theme_color_override("font_color", UiTheme.ACCENT)
		nb.add_child(b)
		var rel := "—" if tag == gs.player_tag else str(int(me["relations"].get(tag, 0)))
		var rel_state := ""
		if tag in me["allies"]:
			rel_state = "Aliado"
		for w in me["wars"]:
			if w["enemy"] == tag:
				rel_state = "En guerra"
		rows.append([nb, str(c["rank"]), VRankingSystem.status_name(c["status"]), "%d" % int(c["total_score"]), rel, rel_state])
	_table(["Nación", "Rk.", "Rango", "Puntos", "Relación", "Estado"], rows, [300, 40, 170, 70, 70, 100])
	_section("Acciones diplomáticas")
	var target := _diplo_selected if _diplo_selected != "" and _diplo_selected != gs.player_tag else ""
	_note("Objetivo: %s. Relaciones, alianzas, garantías, acceso militar, influencia/esferas y Casus Belli se activan en las fases 9 y 11." % (gs.country_name(target) if target != "" else "ninguno (elige una nación en la tabla)"))
	var hb := HFlowContainer.new()
	for a in ["Mejorar relaciones", "Empeorar relaciones", "Proponer alianza", "Garantizar independencia", "Pedir acceso militar",
			"Aumentar opinión", "Añadir a la esfera", "Justificar guerra", "Declarar guerra"]:
		var b := UiTheme.button(a)
		b.disabled = true
		b.tooltip_text = "Disponible en la fase de diplomacia/guerra."
		hb.add_child(b)
	_content.add_child(hb)


# ---------------------------------------------------------------- militar
func _build_military() -> void:
	var c := _country()
	var types := VPopulationSystem.sizes_by(gs, gs.owned_provinces(gs.player_tag), "type")
	_section("Fuerzas armadas")
	_table(["Concepto", "Valor"], [
		["Brigadas", str(c["military"]["brigades"])],
		["Barcos", str(c["military"]["ships"])],
		["Soldier POPs (reclutables)", UiTheme.fmt_int(types.get("soldiers", 0))],
		["Oficiales (generan leadership)", UiTheme.fmt_int(types.get("officers", 0))],
		["Puntuación militar", "%d" % int(c["military_score"])],
		["Cansancio bélico", "%.1f" % float(c["war_exhaustion"])],
	], [320, 200])
	_section("Fortificaciones y bases navales")
	var rows := []
	for id in gs.owned_provinces(gs.player_tag):
		var p: Dictionary = gs.provinces[id]
		if int(p["fort"]) > 0 or int(p["naval_base"]) > 0:
			var b := UiTheme.button(p["name"], func(): province_focus.emit(id))
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows.append([b, str(p["fort"]), str(p["naval_base"])])
	_table(["Provincia", "Fortificación", "Base naval"], rows, [300, 100, 100])
	_note("Ejércitos y flotas físicos en el mapa (movimiento provincia a provincia, supply, attrition, generales, transporte naval) llegan en las fases 10–12.")


func _build_alerts() -> void:
	var c := _country()
	_section("Alertas")
	var any := false
	for w in c["wars"]:
		_note("En guerra: %s contra %s." % [w["name"], gs.country_name(w["enemy"])])
		any = true
	if float(c["income_daily"]) < float(c["expense_daily"]):
		_note("El presupuesto tiene balance diario negativo.")
		any = true
	if not any:
		_note("Sin alertas.")
