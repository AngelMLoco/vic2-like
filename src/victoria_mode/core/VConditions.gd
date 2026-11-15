class_name VConditions
extends RefCounted
## Evaluador de condiciones data-driven para POPs (promoción, issues, movimientos)
## y para naciones (inventos). Añadir una clave nueva = añadir una rama aquí.
##
## ctx (POP): {"vacancy": {tipo: plazas}, "civilized": bool, "military_spending": float}


static func pop_ok(gs: VGameState, s: int, cond: Dictionary, tag: String, ctx: Dictionary) -> bool:
	var ps := gs.pops
	for k in cond:
		var v = cond[k]
		match k:
			"min_literacy":
				if ps.literacy[s] < float(v): return false
			"max_literacy":
				if ps.literacy[s] > float(v): return false
			"min_life":
				if ps.life[s] < float(v): return false
			"max_life":
				if ps.life[s] > float(v): return false
			"min_everyday":
				if ps.everyday[s] < float(v): return false
			"max_everyday":
				if ps.everyday[s] > float(v): return false
			"min_luxury":
				if ps.luxury[s] < float(v): return false
			"min_unemployment":
				if 1.0 - ps.employment[s] < float(v): return false
			"max_unemployment":
				if 1.0 - ps.employment[s] > float(v): return false
			"min_cash_per_capita":
				if ps.cash[s] / maxf(1.0, float(ps.size[s])) < float(v): return false
			"max_cash_per_capita":
				if ps.cash[s] / maxf(1.0, float(ps.size[s])) > float(v): return false
			"min_consciousness":
				if ps.consciousness[s] < float(v): return false
			"min_militancy":
				if ps.militancy[s] < float(v): return false
			"max_militancy":
				if ps.militancy[s] > float(v): return false
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


## Versión precompilada de pop_ok para bucles calientes: [[código, valor], …] con códigos enteros
## (comparar enteros es mucho más barato que el match por cadenas). Las claves sin código rápido
## se evalúan con pop_ok (código -1).
const _POP_CODES := {"min_literacy": 0, "max_literacy": 1, "min_life": 2, "max_life": 3, "min_everyday": 4,
	"max_everyday": 5, "min_luxury": 6, "min_unemployment": 7, "max_unemployment": 8, "min_cash_per_capita": 9,
	"max_cash_per_capita": 10, "min_consciousness": 11, "min_militancy": 12, "max_militancy": 13, "vacancy": 14}


static func compile_pop(cond: Dictionary) -> Array:
	var out := []
	var rest := {}
	for k in cond:
		if _POP_CODES.has(k):
			out.append([int(_POP_CODES[k]), cond[k] if k == "vacancy" else float(cond[k])])
		else:
			rest[k] = cond[k]
	if not rest.is_empty():
		out.append([-1, rest])
	return out


static func pop_ok_compiled(gs: VGameState, s: int, compiled: Array, tag: String, ctx: Dictionary) -> bool:
	var ps := gs.pops
	for e in compiled:
		var code: int = e[0]
		match code:
			0:
				if ps.literacy[s] < e[1]: return false
			1:
				if ps.literacy[s] > e[1]: return false
			2:
				if ps.life[s] < e[1]: return false
			3:
				if ps.life[s] > e[1]: return false
			4:
				if ps.everyday[s] < e[1]: return false
			5:
				if ps.everyday[s] > e[1]: return false
			6:
				if ps.luxury[s] < e[1]: return false
			7:
				if 1.0 - ps.employment[s] < e[1]: return false
			8:
				if 1.0 - ps.employment[s] > e[1]: return false
			9:
				if ps.cash[s] / maxf(1.0, float(ps.size[s])) < e[1]: return false
			10:
				if ps.cash[s] / maxf(1.0, float(ps.size[s])) > e[1]: return false
			11:
				if ps.consciousness[s] < e[1]: return false
			12:
				if ps.militancy[s] < e[1]: return false
			13:
				if ps.militancy[s] > e[1]: return false
			14:
				if int(ctx.get("vacancy", {}).get(e[1], 0)) <= 0: return false
			_:
				if not pop_ok(gs, s, e[1], tag, ctx): return false
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
