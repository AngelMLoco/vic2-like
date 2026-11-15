class_name VConditions
extends RefCounted
## Evaluador de condiciones data-driven para POPs (promoción, issues, movimientos)
## y para naciones (inventos). Añadir una clave nueva = añadir una rama aquí.
##
## ctx (POP): {"vacancy": {tipo: plazas}, "civilized": bool, "military_spending": float}


static func pop_ok(gs: VGameState, pop: Dictionary, cond: Dictionary, tag: String, ctx: Dictionary) -> bool:
	var needs: Dictionary = pop["needs_satisfaction"]
	for k in cond:
		var v = cond[k]
		match k:
			"min_literacy":
				if float(pop["literacy"]) < float(v): return false
			"max_literacy":
				if float(pop["literacy"]) > float(v): return false
			"min_life":
				if float(needs["life"]) < float(v): return false
			"max_life":
				if float(needs["life"]) > float(v): return false
			"min_everyday":
				if float(needs["everyday"]) < float(v): return false
			"max_everyday":
				if float(needs["everyday"]) > float(v): return false
			"min_luxury":
				if float(needs["luxury"]) < float(v): return false
			"min_unemployment":
				if 1.0 - float(pop["employment"]) < float(v): return false
			"max_unemployment":
				if 1.0 - float(pop["employment"]) > float(v): return false
			"min_cash_per_capita":
				if float(pop["cash"]) / maxf(1.0, float(pop["size"])) < float(v): return false
			"max_cash_per_capita":
				if float(pop["cash"]) / maxf(1.0, float(pop["size"])) > float(v): return false
			"min_consciousness":
				if float(pop["consciousness"]) < float(v): return false
			"min_militancy":
				if float(pop["militancy"]) < float(v): return false
			"max_militancy":
				if float(pop["militancy"]) > float(v): return false
			"vacancy":
				if int(ctx.get("vacancy", {}).get(v, 0)) <= 0: return false
			"civilized":
				if bool(ctx.get("civilized", false)) != bool(v): return false
			"min_military_spending":
				if float(ctx.get("military_spending", 0.0)) < float(v): return false
			"max_military_spending":
				if float(ctx.get("military_spending", 0.0)) > float(v): return false
			"reform_min":
				for r in v:
					if gs.reform_level(tag, r) < int(v[r]): return false
			"reform_max":
				for r in v:
					if gs.reform_level(tag, r) > int(v[r]): return false
	return true


static func country_ok(gs: VGameState, tag: String, cond: Dictionary) -> bool:
	var c: Dictionary = gs.countries[tag]
	for k in cond:
		var v = cond[k]
		match k:
			"min_literacy":
				if float(c.get("literacy", 0.0)) < float(v): return false
			"min_prestige":
				if float(c.get("prestige", 0.0)) < float(v): return false
			"civilized":
				if bool(c.get("civilized", true)) != bool(v): return false
			"has_tech":
				if not (v in c.get("technologies", [])): return false
			"flag":
				if not gs.flags.get(v, false): return false
	return true
