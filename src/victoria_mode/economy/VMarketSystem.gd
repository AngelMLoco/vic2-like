class_name VMarketSystem
extends RefCounted
## Mercado de bienes en tres niveles:  interno (nación) → esfera (líder + miembros) → mundial.
##
## Durante el mes, productores y compradores registran oferta y demanda en su mercado interno
## (add_supply / add_demand) usando los precios y ratios de llenado del mes anterior.
## Al final del mes clear_month():
##   1. casa oferta y demanda dentro de cada nación;
##   2. los excedentes/déficits pasan a la esfera (si la hay) y después al mercado mundial,
##      donde los importadores se atienden por orden de ranking (prioridad de las potencias);
##   3. calcula para cada nación y bien: fill_buy (fracción de la demanda atendida),
##      fill_sell (fracción de la oferta vendida), importaciones y exportaciones;
##   4. ajusta el precio mundial según demanda/oferta, con límites [price_min, price_max] × base;
##   5. cobra aranceles a las importaciones y guarda historial.
##
## Estado en gs.market (se guarda en la partida).


static func setup_new_game(gs: VGameState) -> void:
	var m := {
		"price": {}, "base": {}, "history": {},
		"acc_supply": {}, "acc_demand": {},
		"fill_buy": {}, "fill_sell": {}, "import_share": {},
		"world": {"supply": {}, "demand": {}},
		"country": {},
		"calibration": {},
	}
	for g in gs.goods:
		var bp := float(gs.goods[g]["base_price"])
		m["price"][g] = bp
		m["base"][g] = bp
		m["history"][g] = [bp]
	gs.market = m
	reset_accumulators(gs)


static func reset_accumulators(gs: VGameState) -> void:
	gs.market["acc_supply"] = {}
	gs.market["acc_demand"] = {}


static func is_available(gs: VGameState, good: String) -> bool:
	var flag: String = gs.goods.get(good, {}).get("unlock_flag", "")
	return flag == "" or gs.flags.get(flag, false)


static func price(gs: VGameState, good: String) -> float:
	return float(gs.market["price"].get(good, 1.0))


## Precio pagado por un comprador de la nación: el arancel encarece la parte importada.
static func buy_price(gs: VGameState, tag: String, good: String) -> float:
	var p := price(gs, good)
	if tag == "":
		return p
	var share := float(gs.market["import_share"].get(tag, {}).get(good, 0.0))
	var tariff := float(gs.countries[tag]["budget"].get("tariffs", 0.0))
	return p * (1.0 + tariff * share)


static func fill_buy(gs: VGameState, tag: String, good: String) -> float:
	return float(gs.market["fill_buy"].get(tag, {}).get(good, 1.0))


static func fill_sell(gs: VGameState, tag: String, good: String) -> float:
	return float(gs.market["fill_sell"].get(tag, {}).get(good, 1.0))


static func add_supply(gs: VGameState, tag: String, good: String, qty: float) -> void:
	if tag == "" or qty <= 0.0:
		return
	var acc: Dictionary = gs.market["acc_supply"]
	if not acc.has(tag):
		acc[tag] = {}
	acc[tag][good] = float(acc[tag].get(good, 0.0)) + qty


static func add_demand(gs: VGameState, tag: String, good: String, qty: float) -> void:
	if tag == "" or qty <= 0.0:
		return
	var acc: Dictionary = gs.market["acc_demand"]
	if not acc.has(tag):
		acc[tag] = {}
	acc[tag][good] = float(acc[tag].get(good, 0.0)) + qty


## Cadena de mercados de una nación (API de esferas): domestic → sphere → world.
static func market_chain(gs: VGameState, tag: String) -> Array:
	var chain := ["domestic:" + tag]
	var leader: String = gs.countries.get(tag, {}).get("sphere_leader", "")
	if leader != "":
		chain.append("sphere:" + leader)
	elif _has_sphere_members(gs, tag):
		chain.append("sphere:" + tag)
	chain.append("world")
	return chain


static func _has_sphere_members(gs: VGameState, leader: String) -> bool:
	for t in gs.countries:
		if gs.countries[t].get("sphere_leader", "") == leader:
			return true
	return false


static func sphere_key(gs: VGameState, tag: String) -> String:
	var leader: String = gs.countries.get(tag, {}).get("sphere_leader", "")
	if leader != "":
		return leader
	return tag if _has_sphere_members(gs, tag) else ""


# --------------------------------------------------------------- casación
static func clear_month(gs: VGameState) -> void:
	var m: Dictionary = gs.market
	var rules: Dictionary = gs.economy_rules
	var acc_s: Dictionary = m["acc_supply"]
	var acc_d: Dictionary = m["acc_demand"]
	var tags := {}
	for t in acc_s:
		tags[t] = true
	for t in acc_d:
		tags[t] = true
	# prioridad de importación: ranking (las potencias primero)
	var order: Array = tags.keys()
	order.sort_custom(func(a, b): return _rank(gs, a) < _rank(gs, b))
	var new_fill_buy := {}
	var new_fill_sell := {}
	var new_import_share := {}
	var country_stats := {}
	var world_s := {}
	var world_d := {}
	for t in order:
		new_fill_buy[t] = {}
		new_fill_sell[t] = {}
		new_import_share[t] = {}
		country_stats[t] = {"supply": acc_s.get(t, {}), "demand": acc_d.get(t, {}), "imports": {}, "exports": {}}
	var spheres := {}
	for t in order:
		var k := sphere_key(gs, t)
		if k != "":
			if not spheres.has(k):
				spheres[k] = []
			spheres[k].append(t)
	# M5.6: liquidación. Los compradores pagan durante el mes con el llenado ESTIMADO del mes anterior; aquí se
	# conoce lo que de verdad compraron. Lo pagado por bienes que no llegaron se devuelve a los POPs de ese país
	# (antes se destruía: con demanda creciente era un drenaje de dinero → deflación tardía).
	var old_fb: Dictionary = m.get("fill_buy", {})
	var refunds := {}
	var settle := bool(rules.get("settle_purchases", true))
	var blockade := {}
	for t in order:
		var br := float(gs.countries.get(t, {}).get("blockade_ratio", 0.0))
		if br > 0.0:
			blockade[t] = br
	for g in gs.goods:
		var excess := {}  # t -> oferta no vendida en casa
		var need := {}  # t -> demanda no atendida en casa
		var sold := {}
		var bought := {}
		var tot_s := 0.0
		var tot_d := 0.0
		for t in order:
			var s := float(acc_s.get(t, {}).get(g, 0.0))
			var d := float(acc_d.get(t, {}).get(g, 0.0))
			tot_s += s
			tot_d += d
			var matched: float = min(s, d)
			sold[t] = matched
			bought[t] = matched
			if s > matched:
				excess[t] = s - matched
			if d > matched:
				need[t] = d - matched
		world_s[g] = tot_s
		world_d[g] = tot_d
		if tot_s <= 0.0 and tot_d <= 0.0:
			continue
		# esferas: intercambio entre miembros antes del mundo
		for k in spheres:
			_trade_pool(spheres[k], excess, need, sold, bought, country_stats, g)
		# bloqueo naval: la parte bloqueada de la costa no exporta ni importa por mar
		var held_excess := {}
		var held_need := {}
		for t in blockade:
			var r := float(blockade[t])
			if excess.has(t):
				held_excess[t] = float(excess[t]) * r
				excess[t] = float(excess[t]) - float(held_excess[t])
			if need.has(t):
				held_need[t] = float(need[t]) * r
				need[t] = float(need[t]) - float(held_need[t])
		# mercado mundial
		_trade_pool(order, excess, need, sold, bought, country_stats, g)
		for t in order:
			var s := float(acc_s.get(t, {}).get(g, 0.0))
			var d := float(acc_d.get(t, {}).get(g, 0.0))
			if s > 0.0:
				new_fill_sell[t][g] = float(sold[t]) / s
			if d > 0.0:
				new_fill_buy[t][g] = float(bought[t]) / d
				if settle:
					var paid_q := d * float(old_fb.get(t, {}).get(g, 1.0))
					if paid_q > float(bought[t]):
						refunds[t] = float(refunds.get(t, 0.0)) + (paid_q - float(bought[t])) * buy_price(gs, t, g)
				var imp := float(country_stats[t]["imports"].get(g, 0.0))
				new_import_share[t][g] = imp / d
				var tariff := float(gs.countries[t]["budget"].get("tariffs", 0.0)) if gs.countries.has(t) else 0.0
				if imp > 0.0 and tariff > 0.0:
					var acc: Dictionary = gs.countries[t]["acc"]
					acc["tariffs"] = float(acc.get("tariffs", 0.0)) + imp * price(gs, g) * tariff
		# precio mundial
		_update_price(gs, g, tot_s, tot_d, rules)
	for t in refunds:
		_refund(gs, String(t), float(refunds[t]))
	m["fill_buy"] = new_fill_buy
	m["fill_sell"] = new_fill_sell
	m["import_share"] = new_import_share
	m["country"] = country_stats
	m["world"] = {"supply": world_s, "demand": world_d}
	reset_accumulators(gs)


## Devuelve a los POPs de una nación (proporcional a su tamaño) lo pagado por bienes que no recibieron.
static func _refund(gs: VGameState, tag: String, amount: float) -> void:
	var c: Dictionary = gs.countries.get(tag, {})
	if c.is_empty() or amount <= 1.0:
		return
	var ps := gs.pops
	var total := maxf(1.0, float(c.get("population", 0)))
	for id in c["provinces"]:
		for s in gs.provinces[id]["pop_slots"]:
			ps.cash[s] += amount * float(ps.size[s]) / total
	VMoney.created(gs, amount, "market_refund")


## Intercambia excedentes por necesidades dentro de un grupo de naciones.
## Los importadores se atienden en orden (ranking); los exportadores venden a prorrata.
static func _trade_pool(members: Array, excess: Dictionary, need: Dictionary, sold: Dictionary, bought: Dictionary, stats: Dictionary, g: String) -> void:
	var avail := 0.0
	for t in members:
		avail += float(excess.get(t, 0.0))
	if avail <= 0.0:
		return
	var total_taken := 0.0
	for t in members:
		var n := float(need.get(t, 0.0))
		if n <= 0.0:
			continue
		var take: float = min(n, avail - total_taken)
		if take <= 0.0:
			break
		total_taken += take
		need[t] = n - take
		bought[t] = float(bought[t]) + take
		stats[t]["imports"][g] = float(stats[t]["imports"].get(g, 0.0)) + take
	if total_taken <= 0.0:
		return
	var ratio := total_taken / avail
	for t in members:
		var e := float(excess.get(t, 0.0))
		if e <= 0.0:
			continue
		var out := e * ratio
		excess[t] = e - out
		sold[t] = float(sold[t]) + out
		stats[t]["exports"][g] = float(stats[t]["exports"].get(g, 0.0)) + out


static func _update_price(gs: VGameState, g: String, s: float, d: float, rules: Dictionary) -> void:
	var m: Dictionary = gs.market
	var base := float(m["base"][g])
	var p := float(m["price"][g])
	var k := float(rules.get("price_adjust", 0.08))
	var pressure := 0.0
	if s <= 0.0 and d > 0.0:
		pressure = 1.0
	elif d <= 0.0 and s > 0.0:
		pressure = -1.0
	elif s > 0.0:
		pressure = clampf((d - s) / max(s, d), -1.0, 1.0)
	p *= 1.0 + k * pressure
	p = clampf(p, base * float(rules.get("price_min", 0.25)), base * float(rules.get("price_max", 4.0)))
	m["price"][g] = p
	var hist: Array = m["history"][g]
	hist.append(p)
	var maxh := int(rules.get("price_history", 24))
	if hist.size() > maxh:
		hist.remove_at(0)


static func _rank(gs: VGameState, tag: String) -> int:
	var r := int(gs.countries.get(tag, {}).get("rank", 0))
	return r if r > 0 else 9999


## Estadística mensual de una nación para un bien: {supply, demand, imports, exports}.
static func country_good(gs: VGameState, tag: String, good: String) -> Dictionary:
	var cs: Dictionary = gs.market.get("country", {}).get(tag, {})
	return {
		"supply": float(cs.get("supply", {}).get(good, 0.0)),
		"demand": float(cs.get("demand", {}).get(good, 0.0)),
		"imports": float(cs.get("imports", {}).get(good, 0.0)),
		"exports": float(cs.get("exports", {}).get(good, 0.0)),
	}
