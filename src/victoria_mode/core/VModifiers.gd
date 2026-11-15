class_name VModifiers
extends RefCounted
## Modificadores nacionales agregados: suma de efectos de tecnologías, inventos, niveles de reforma y
## modificadores de eventos/decisiones/magia (VScopedState).
## Se recalculan solo cuando cambia alguna de esas fuentes (no cada tick).
## Claves usadas por los sistemas: rgo_efficiency, rgo_size, factory_efficiency, factory_throughput,
## factory_wage, artisan_efficiency, research, literacy_growth, pop_growth, tax_efficiency,
## admin_efficiency, consciousness_growth, militancy_growth, worker_militancy, ideology_drift,
## socialist_drift, pension, unemployment_benefit, social_cost, bank_capacity, military_strength,
## naval_strength, leadership, trade_efficiency.


static func recompute(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var mods := {}
	for t in c.get("technologies", []):
		_add(mods, gs.technologies.get(t, {}).get("effects", {}))
	for inv in c.get("inventions", []):
		_add(mods, gs.inventions.get(inv, {}).get("effects", {}))
	var reforms: Dictionary = c.get("reforms", {})
	for rid in reforms:
		var r: Dictionary = gs.reforms.get(rid, {})
		var levels: Array = r.get("levels", [])
		var lvl := int(reforms[rid])
		if lvl >= 0 and lvl < levels.size():
			_add(mods, levels[lvl].get("effects", {}))
	# M4: modificadores de eventos, decisiones y magia (temporales o permanentes)
	for m in VScopedState.country_modifiers(gs, tag):
		_add(mods, VScopedState.modifier_effects(gs, m))
	c["mods"] = mods


static func _add(mods: Dictionary, effects: Dictionary) -> void:
	for k in effects:
		var v = effects[k]
		if v is float or v is int:
			mods[k] = float(mods.get(k, 0.0)) + float(v)
		else:
			mods[k] = v


## Descripción legible de un diccionario de efectos (para tooltips).
static func describe(effects: Dictionary) -> String:
	var parts := []
	for k in effects:
		var v = effects[k]
		if v is float or v is int:
			parts.append("%s %+.0f%%" % [k.replace("_", " "), float(v) * 100.0] if abs(float(v)) < 5.0 else "%s %+.1f" % [k, float(v)])
		else:
			parts.append("%s: %s" % [k, str(v)])
	return ", ".join(parts)
