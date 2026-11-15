class_name VMapModes
extends RefCounted
## Registro de mapmodes. Todos reutilizan la misma geometría: un mapmode solo decide
## el color de cada provincia (y opcionalmente de cada zona marítima).
## Para añadir uno nuevo: registrar en MODES y añadir una rama en color_of().

const UNOWNED := Color("9a9078")
const NONE := Color(0, 0, 0, 0)

## id, nombre, tecla, disponible, descripción
const MODES := [
	{"id": "political", "name": "Político", "key": "1", "available": true, "desc": "Fronteras y colores nacionales."},
	{"id": "diplomatic", "name": "Diplomático", "key": "2", "available": true, "desc": "Relaciones de la nación seleccionada: aliados, rivales, guerras."},
	{"id": "resources", "name": "Recursos (RGO)", "key": "3", "available": true, "desc": "Recurso primario de cada provincia."},
	{"id": "population", "name": "Población", "key": "4", "available": true, "desc": "Densidad de población."},
	{"id": "culture", "name": "Cultura", "key": "5", "available": true, "desc": "Cultura mayoritaria de cada provincia."},
	{"id": "religion", "name": "Religión", "key": "6", "available": true, "desc": "Religión mayoritaria de cada provincia."},
	{"id": "industry", "name": "Economía / Industria", "key": "7", "available": true, "desc": "Niveles de fábrica por estado."},
	{"id": "military", "name": "Militar", "key": "8", "available": true, "desc": "Control: propio, aliado, enemigo, ocupado (rayado), rebeldes; fortificaciones y bases navales."},
	{"id": "terrain", "name": "Terreno", "key": "9", "available": true, "desc": "Tipo de terreno."},
	{"id": "states", "name": "Estados", "key": "0", "available": true, "desc": "Cada parte de estado con su propio color."},
	{"id": "infrastructure", "name": "Infraestructura", "key": "", "available": true, "desc": "Nivel de infraestructura."},
	{"id": "literacy", "name": "Alfabetización", "key": "", "available": true, "desc": "Alfabetización media de los POPs."},
	{"id": "rebels", "name": "Rebelión", "key": "", "available": true, "desc": "Militancia media de los POPs y provincias en manos rebeldes (negro)."},
	{"id": "sphere", "name": "Esferas", "key": "", "available": true, "desc": "Grandes Potencias y los países de su esfera de influencia."},
	{"id": "migration", "name": "Desempleo", "key": "", "available": true, "desc": "Desempleo de los POPs pobres (principal motor de la migración)."},
	{"id": "needs", "name": "Necesidades", "key": "", "available": true, "desc": "Satisfacción de necesidades vitales de los POPs pobres."},
	{"id": "colonial", "name": "Colonización", "key": "", "available": false, "desc": "Disponible con la fase de colonización."},
	{"id": "supply", "name": "Suministro", "key": "", "available": true, "desc": "Límite de suministro (brigadas) para la nación de referencia."},
]


static func mode_def(id: String) -> Dictionary:
	for m in MODES:
		if m["id"] == id:
			return m
	return {}


## Calcula el array de colores (índice = id de provincia) para un mapmode.
## focus_tag: nación de referencia (jugador o nación seleccionada).
static func compute(gs: VGameState, mode: String, focus_tag: String) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(gs.max_id + 1)
	var ctx := _context(gs, mode, focus_tag)
	for id in range(1, gs.max_id + 1):
		colors[id] = color_of(gs, mode, id, focus_tag, ctx)
	return colors


static func _context(gs: VGameState, mode: String, focus_tag: String) -> Dictionary:
	var ctx := {}
	match mode:
		"population":
			var mx := 1.0
			for id in range(1, gs.first_sea_id):
				var p: Dictionary = gs.provinces[id]
				mx = max(mx, float(p["population"]) / max(1.0, float(p["area_km2"])))
			ctx["max_density"] = mx
		"industry":
			var levels := {}
			var mx := 1
			for key in gs.state_instances:
				var si: Dictionary = gs.state_instances[key]
				var l := 0
				for f in si["factories"]:
					l += int(f["level"])
				levels[key] = l
				mx = max(mx, l)
			ctx["levels"] = levels
			ctx["max_level"] = mx
		"military":
			var mx := 1.0
			for tag in gs.countries:
				mx = max(mx, float(gs.countries[tag]["military_score"]))
			ctx["max_mil"] = mx
		"culture", "religion", "literacy":
			pass
	return ctx


static func color_of(gs: VGameState, mode: String, id: int, focus_tag: String, ctx: Dictionary) -> Color:
	var p: Dictionary = gs.provinces[id]
	if id >= gs.first_sea_id:
		return NONE
	var owner: String = p["owner"]
	match mode:
		"political":
			return gs.country_color(owner)
		"diplomatic":
			return _diplomatic(gs, owner, focus_tag)
		"resources":
			return gs.goods.get(p["rgo"], {}).get("color_obj", UNOWNED)
		"population":
			var d: float = float(p["population"]) / max(1.0, float(p["area_km2"]))
			var t: float = clamp(log(1.0 + d) / log(1.0 + float(ctx["max_density"])), 0.0, 1.0)
			return Color("2a3b2a").lerp(Color("f2e27a"), t)
		"culture":
			var c: String = _majority(p, "culture", p.get("culture", ""))
			return gs.cultures.get(c, {}).get("color_obj", UNOWNED)
		"religion":
			var r: String = _majority(p, "religion", p.get("religion", ""))
			return gs.religions.get(r, {}).get("color_obj", UNOWNED)
		"industry":
			if owner == "":
				return UNOWNED.darkened(0.3)
			var key := gs.state_instance_key(p["state"], owner)
			var lvl := int(ctx["levels"].get(key, 0))
			if lvl == 0:
				return Color("4a4638").lerp(gs.country_color(owner), 0.15)
			var t := float(lvl) / float(ctx["max_level"])
			return Color("8a5a2a").lerp(Color("ffcc4a"), sqrt(t))
		"military":
			var ctrl: String = p["controller"]
			if ctrl == VGameState.REBEL_TAG:
				return Color("1a1a1a")
			if owner == "":
				return UNOWNED.darkened(0.3)
			var c2 := Color("6a6658")
			if focus_tag != "":
				if ctrl == focus_tag:
					c2 = Color("3f8a3a")
				elif VWarSystem.at_war_with(gs, focus_tag, ctrl):
					c2 = Color("b8342a")
				elif VDiplomacySystem.are_allied(gs, focus_tag, ctrl):
					c2 = Color("3a6ab0")
			if int(p.get("fort", 0)) > 0:
				c2 = c2.lightened(0.25)
			return c2
		"sphere":
			if owner == "":
				return UNOWNED.darkened(0.35)
			if VInfluenceSystem.is_gp(gs, owner):
				return gs.country_color(owner)
			var leader: String = gs.countries[owner].get("sphere_leader", "")
			if leader != "":
				return gs.country_color(leader).lerp(Color.WHITE, 0.35)
			return Color("5a564a")
		"supply":
			if owner == "":
				return UNOWNED.darkened(0.35)
			var lim := VSupplySystem.supply_limit(gs, focus_tag if focus_tag != "" else owner, id)
			return Color("6a2a1a").lerp(Color("8ad86a"), clampf(lim / 16.0, 0.0, 1.0))
		"terrain":
			return gs.terrain_types.get(p["terrain"], {}).get("color_obj", UNOWNED)
		"states":
			var base := gs.country_color(owner) if owner != "" else UNOWNED
			var h := gs.state_instance_key(p["state"], owner).hash()
			return base.lerp(Color.from_hsv(float(h & 255) / 255.0, 0.5, 0.85), 0.45)
		"infrastructure":
			var lv := int(p.get("infrastructure", 0))
			return Color("3e3a30").lerp(Color("e8d07a"), clamp(float(lv) / 3.0, 0.0, 1.0)) if owner != "" else UNOWNED.darkened(0.35)
		"needs":
			if owner == "":
				return UNOWNED.darkened(0.35)
			return Color("8a2a1a").lerp(Color("e8d07a"), clampf(float(p.get("avg_life", 1.0)) * 1.4 - 0.4, 0.0, 1.0)).lerp(Color("5ab05a"), clampf(float(p.get("avg_life", 1.0)) - 0.85, 0.0, 0.15) / 0.15)
		"migration":
			if owner == "":
				return UNOWNED.darkened(0.35)
			return Color("3e5a3a").lerp(Color("e05a3a"), clampf(float(p.get("unemployment", 0.0)) * 4.0, 0.0, 1.0))
		"rebels":
			if owner == "":
				return UNOWNED.darkened(0.35)
			if p["controller"] == VGameState.REBEL_TAG:
				return Color("111111")
			var mil := VPopulationSystem.weighted_average(gs, [id], "militancy")
			return Color("4a5a4a").lerp(Color("c81a1a"), clampf(mil / 5.0, 0.0, 1.0))
		"literacy":
			var lit := VPopulationSystem.weighted_average(gs, [id], "literacy")
			return Color("4a2a2a").lerp(Color("7ad8a8"), clamp(lit * 1.6, 0.0, 1.0))
	return gs.country_color(owner)


static func _majority(p: Dictionary, field: String, fallback: String) -> String:
	var counts := {}
	for pop in p.get("pops", []):
		counts[pop[field]] = counts.get(pop[field], 0) + int(pop["size"])
	var best := fallback
	var best_n := -1
	for k in counts:
		if counts[k] > best_n:
			best_n = counts[k]
			best = k
	return best


static func _diplomatic(gs: VGameState, owner: String, focus: String) -> Color:
	if owner == "":
		return UNOWNED.darkened(0.25)
	if focus == "" or not gs.countries.has(focus):
		return gs.country_color(owner).darkened(0.4)
	if owner == focus:
		return Color("4fc24a")
	var fc: Dictionary = gs.countries[focus]
	if VWarSystem.at_war_with(gs, focus, owner):
		return Color("d8342a")
	if owner in fc["allies"]:
		return Color("3a7ad8")
	if gs.countries[owner].get("sphere_leader", "") == focus:
		return Color("7ac8e8")
	var rel := float(fc["relations"].get(owner, 0))
	if rel >= 0.0:
		return Color("8a8470").lerp(Color("b8e0a0"), rel / 200.0)
	return Color("8a8470").lerp(Color("e08a5a"), -rel / 200.0)


## Elementos de leyenda para el mapmode (lista de [color, texto]).
static func legend(gs: VGameState, mode: String) -> Array:
	match mode:
		"diplomatic":
			return [[Color("4fc24a"), "Nación seleccionada"], [Color("3a7ad8"), "Aliado"], [Color("d8342a"), "En guerra"],
				[Color("7ac8e8"), "En su esfera"], [Color("b8e0a0"), "Buenas relaciones"], [Color("e08a5a"), "Malas relaciones"]]
		"population":
			return [[Color("2a3b2a"), "Despoblado"], [Color("f2e27a"), "Muy denso"]]
		"industry":
			return [[Color("4a4638"), "Sin industria"], [Color("8a5a2a"), "Poca industria"], [Color("ffcc4a"), "Gran centro industrial"]]
		"military":
			return [[Color("3f8a3a"), "Control propio"], [Color("3a6ab0"), "Aliado"], [Color("b8342a"), "Enemigo"], [Color("1a1a1a"), "Rebeldes"]]
		"sphere":
			return [[Color("5a564a"), "Fuera de esferas"], [Color("c8c8c8"), "Color claro = en la esfera de esa potencia"]]
		"supply":
			return [[Color("6a2a1a"), "Suministro escaso"], [Color("8ad86a"), "Suministro abundante"]]
		"infrastructure":
			return [[Color("3e3a30"), "Sin infraestructura"], [Color("e8d07a"), "Infraestructura alta"]]
		"literacy":
			return [[Color("4a2a2a"), "Analfabeta"], [Color("7ad8a8"), "Alfabetizada"]]
		"needs":
			return [[Color("8a2a1a"), "Hambre"], [Color("e8d07a"), "Vida cubierta en parte"], [Color("5ab05a"), "Vida cubierta"]]
		"migration":
			return [[Color("3e5a3a"), "Pleno empleo"], [Color("e05a3a"), "Paro ≥ 25%"]]
		"rebels":
			return [[Color("4a5a4a"), "Calma"], [Color("c81a1a"), "Militancia alta"], [Color("111111"), "Control rebelde"]]
	return []
