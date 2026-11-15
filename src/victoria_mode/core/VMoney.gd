class_name VMoney
extends RefCounted
## Auditoría monetaria.
##
## En este modelo el dinero se CREA al vender al mercado (el productor cobra precio × vendido)
## y se DESTRUYE al comprar (el comprador paga). Otras fuentes/sumideros explícitos: préstamos al
## Estado, intereses, amortizaciones, construcción y reserva militar pagadas al mercado,
## aranceles, inversión privada, pérdidas de fábricas perdonadas, reapertura de fábricas.
## Todo lo demás son transferencias (impuestos, salarios, subsidios, beneficios, depósitos, migración).
##
## created()/destroyed() acumulan por categoría. audit() mide los activos monetarios
##   M = efectivo de POPs + depósitos de POPs + caja de fábricas + tesoros
## y compara ΔM con (creado − destruido). El residuo debe ser ≈ 0; si no, hay creación o
## destrucción accidental de dinero (un sumidero/fuente no registrado).


static func _ledger(gs: VGameState) -> Dictionary:
	if not gs.market.has("money_ledger"):
		gs.market["money_ledger"] = {"created": {}, "destroyed": {}}
	return gs.market["money_ledger"]


static func created(gs: VGameState, amount: float, category: String) -> void:
	if amount == 0.0:
		return
	var l: Dictionary = _ledger(gs)["created"]
	l[category] = float(l.get(category, 0.0)) + amount


static func destroyed(gs: VGameState, amount: float, category: String) -> void:
	if amount == 0.0:
		return
	var l: Dictionary = _ledger(gs)["destroyed"]
	l[category] = float(l.get(category, 0.0)) + amount


## Activos monetarios en este instante (recorre todos los POPs: usar con moderación).
static func snapshot(gs: VGameState) -> Dictionary:
	var pop_cash := 0.0
	var pop_bank := 0.0
	for id in range(1, gs.first_sea_id):
		for pop in gs.provinces[id]["pops"]:
			pop_cash += float(pop["cash"])
			pop_bank += float(pop.get("bank", 0.0))
	var factory_cash := 0.0
	for key in gs.state_instances:
		for f in gs.state_instances[key]["factories"]:
			factory_cash += float(f.get("cash", 0.0))
	var treasury := 0.0
	var debt := 0.0
	var lent := 0.0
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		treasury += float(c.get("treasury", 0.0))
		debt += float(c.get("debt", 0.0))
		lent += float(c.get("bank", {}).get("lent", 0.0))
	return {"pop_cash": pop_cash, "pop_bank": pop_bank, "factory_cash": factory_cash, "treasury": treasury,
		"total": pop_cash + pop_bank + factory_cash + treasury, "debt": debt, "bank_lent": lent}


## Compara con la instantánea anterior. Guarda el informe en gs.market["money_audit"].
static func audit(gs: VGameState) -> Dictionary:
	var snap := snapshot(gs)
	var l := _ledger(gs)
	var c_tot := 0.0
	var d_tot := 0.0
	for k in l["created"]:
		c_tot += float(l["created"][k])
	for k in l["destroyed"]:
		d_tot += float(l["destroyed"][k])
	var prev: Dictionary = gs.market.get("money_snapshot", {})
	var report := {"date": gs.date.text(), "snapshot": snap, "created": l["created"].duplicate(), "destroyed": l["destroyed"].duplicate(),
		"created_total": c_tot, "destroyed_total": d_tot}
	if not prev.is_empty():
		var delta := float(snap["total"]) - float(prev["total"])
		report["delta"] = delta
		report["explained"] = c_tot - d_tot
		report["residual"] = delta - (c_tot - d_tot)
		report["residual_ratio"] = absf(float(report["residual"])) / maxf(1.0, float(prev["total"]))
	gs.market["money_snapshot"] = snap
	gs.market["money_ledger"] = {"created": {}, "destroyed": {}}
	gs.market["money_audit"] = report
	return report


static func describe(report: Dictionary) -> String:
	if report.is_empty():
		return "Sin auditoría todavía."
	var s: Dictionary = report["snapshot"]
	var lines := ["%s — activos %.0f (POPs efectivo %.0f · depósitos %.0f · fábricas %.0f · tesoros %.0f) · deuda %.0f" % [
		report["date"], float(s["total"]), float(s["pop_cash"]), float(s["pop_bank"]), float(s["factory_cash"]), float(s["treasury"]), float(s["debt"])]]
	if report.has("delta"):
		lines.append("Δ %.0f = creado %.0f − destruido %.0f + residuo %.0f (%.3f%%)" % [float(report["delta"]), float(report["created_total"]),
			float(report["destroyed_total"]), float(report["residual"]), float(report["residual_ratio"]) * 100.0])
	return "\n".join(lines)
