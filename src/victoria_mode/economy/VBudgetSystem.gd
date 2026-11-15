class_name VBudgetSystem
extends RefCounted
## Presupuesto nacional.
##
## Ingresos: impuestos a pobres/clase media/ricos (sobre la renta real de los POPs, cobrados al
## acreditarla, con eficiencia según la administración), aranceles (sobre importaciones), otros.
## Gastos: educación (salario del clero), administración (burócratas), salarios militares
## (soldados y oficiales), reserva militar (compra real de bienes militares al mercado),
## gasto social (subsidios de paro, pensiones, sanidad/escuelas), subvenciones a fábricas,
## construcción e intereses de la deuda.
## Si el tesoro queda en negativo se pide prestado: primero al banco nacional (depósitos de POPs),
## después a prestamistas extranjeros con más interés.
##
## Los flujos se acumulan durante el mes en country["acc"] y se liquidan en settle_month().

const INCOME_KEYS := ["tax_poor", "tax_middle", "tax_rich", "tariffs", "other"]
const EXPENSE_KEYS := ["education", "administration", "military_wages", "stockpile", "social", "subsidies", "construction", "interest"]
const SLIDER_FOR := {"education": "education", "administration": "administration", "military": "military", "leadership": "military"}
const EXPENSE_FOR_JOB := {"education": "education", "administration": "administration", "military": "military_wages", "leadership": "military_wages"}


static func new_acc() -> Dictionary:
	var a := {}
	for k in INCOME_KEYS:
		a[k] = 0.0
	for k in EXPENSE_KEYS:
		a[k] = 0.0
	return a


static func setup_new_game(gs: VGameState) -> void:
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		c["acc"] = new_acc()
		c["budget_last"] = new_acc()
		c["debt"] = 0.0
		c["debt_foreign"] = 0.0
		c["bank"] = {"deposits": 0.0, "lent": 0.0}
		c["stockpile"] = {}
		c["pay_ratio"] = 1.0
		c["admin_efficiency"] = 0.6
		c["tax_efficiency"] = 0.8
		c["monthly_balance"] = 0.0


## Acredita renta a un POP descontando el impuesto de su estrato.
static func credit_income(gs: VGameState, tag: String, pop: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	var net := amount
	if tag != "":
		var c: Dictionary = gs.countries[tag]
		var strata: String = gs.pop_types.get(pop["type"], {}).get("strata", "poor")
		var rate := float(c["budget"].get("tax_" + strata, 0.0)) * float(c.get("tax_efficiency", 0.8))
		var tax := amount * rate
		c["acc"]["tax_" + strata] = float(c["acc"]["tax_" + strata]) + tax
		net = amount - tax
	pop["cash"] = float(pop["cash"]) + net
	pop["income_acc"] = float(pop.get("income_acc", 0.0)) + net


## Transferencia sin impuestos (subsidios, pensiones).
static func transfer(pop: Dictionary, amount: float) -> void:
	pop["cash"] = float(pop["cash"]) + amount
	pop["income_acc"] = float(pop.get("income_acc", 0.0)) + amount


static func add_expense(gs: VGameState, tag: String, key: String, amount: float) -> void:
	if tag == "" or amount == 0.0:
		return
	var acc: Dictionary = gs.countries[tag]["acc"]
	acc[key] = float(acc.get(key, 0.0)) + amount


## Fracción del sueldo estatal que se paga para un tipo de empleo (slider × capacidad de pago).
static func gov_pay_factor(c: Dictionary, job: String) -> float:
	var slider: String = SLIDER_FOR.get(job, "")
	if slider == "":
		return 0.0
	return float(c["budget"].get(slider, 0.0)) * float(c.get("pay_ratio", 1.0))


## Compra de la reserva militar al mercado (gasto real de bienes).
static func buy_stockpile(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var slider := float(c["budget"].get("stockpile", 0.0))
	if slider <= 0.0:
		return
	var mil: Dictionary = c["military"]
	var per_brigade: Dictionary = gs.economy_rules.get("stockpile_goods", {})
	var per_ship: Dictionary = gs.economy_rules.get("stockpile_per_ship", {})
	var want := {}
	for g in per_brigade:
		want[g] = float(per_brigade[g]) * float(mil.get("brigades", 0)) * slider
	for g in per_ship:
		want[g] = float(want.get(g, 0.0)) + float(per_ship[g]) * float(mil.get("ships", 0)) * slider
	var cost := 0.0
	for g in want:
		var q := float(want[g])
		if q <= 0.0:
			continue
		VMarketSystem.add_demand(gs, tag, g, q)
		var got := q * VMarketSystem.fill_buy(gs, tag, g)
		cost += got * VMarketSystem.buy_price(gs, tag, g)
		c["stockpile"][g] = float(c["stockpile"].get(g, 0.0)) + got
	VMoney.destroyed(gs, cost, "stockpile")
	add_expense(gs, tag, "stockpile", cost)


## Liquidación mensual: ingresos − gastos, deuda, banco, eficiencia administrativa, IA.
static func settle_month(gs: VGameState, tag: String, is_player: bool) -> void:
	var c: Dictionary = gs.countries[tag]
	var rules: Dictionary = gs.economy_rules
	var acc: Dictionary = c["acc"]
	buy_stockpile(gs, tag)
	var debt := float(c["debt"])
	var foreign := float(c.get("debt_foreign", 0.0))
	var domestic := debt - foreign
	acc["interest"] = (domestic * float(rules.get("interest_domestic", 0.04)) + foreign * float(rules.get("interest_foreign", 0.09))) / 12.0
	var income := 0.0
	for k in INCOME_KEYS:
		income += float(acc.get(k, 0.0))
	var expense := 0.0
	for k in EXPENSE_KEYS:
		expense += float(acc.get(k, 0.0))
	var balance := income - expense
	c["treasury"] = float(c["treasury"]) + balance
	VMoney.created(gs, float(acc.get("tariffs", 0.0)), "tariffs")
	VMoney.destroyed(gs, float(acc.get("construction", 0.0)), "construction")
	VMoney.destroyed(gs, float(acc.get("interest", 0.0)), "interest")
	# deuda: pedir prestado si el tesoro es negativo
	if float(c["treasury"]) < 0.0:
		var need := -float(c["treasury"])
		var bank: Dictionary = c["bank"]
		var avail: float = maxf(0.0, float(bank["deposits"]) * (1.0 + gs.mod(tag, "bank_capacity")) - float(bank["lent"]))
		var from_bank: float = min(need, avail)
		bank["lent"] = float(bank["lent"]) + from_bank
		c["debt"] = float(c["debt"]) + need
		c["debt_foreign"] = foreign + (need - from_bank)
		c["treasury"] = 0.0
		VMoney.created(gs, need, "state_borrowing")
	elif debt > 0.0 and float(c["treasury"]) > expense * 3.0:
		var repay: float = min(debt, (float(c["treasury"]) - expense * 3.0) * 0.5)
		c["treasury"] = float(c["treasury"]) - repay
		c["debt"] = debt - repay
		VMoney.destroyed(gs, repay, "debt_repayment")
		var f_rep: float = min(foreign, repay)
		c["debt_foreign"] = foreign - f_rep
		c["bank"]["lent"] = maxf(0.0, float(c["bank"]["lent"]) - (repay - f_rep))
	var cap: float = maxf(500.0, income * float(rules.get("max_debt_months_of_income", 36)))
	c["pay_ratio"] = 0.6 if float(c["debt"]) > cap else 1.0
	c["budget_last"] = acc.duplicate()
	c["monthly_income"] = income
	c["monthly_expense"] = expense
	c["monthly_balance"] = balance
	c["income_daily"] = income / 30.0
	c["expense_daily"] = expense / 30.0
	c["acc"] = new_acc()
	_update_efficiency(gs, tag)
	if not is_player:
		_ai_adjust(c, balance, expense)


static func _update_efficiency(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var pop := float(max(1, int(c.get("population", 1))))
	var bureau := float(c.get("type_sizes", {}).get("bureaucrats", 0))
	var share := bureau / pop
	var admin: float = clampf(share / 0.008 * (0.4 + 0.6 * float(c["budget"]["administration"])) * (1.0 + gs.mod(tag, "admin_efficiency")), 0.05, 1.0)
	c["admin_efficiency"] = admin
	c["tax_efficiency"] = clampf(float(gs.economy_rules.get("tax_efficiency_base", 0.5)) + 0.5 * admin + gs.mod(tag, "tax_efficiency"), 0.2, 1.0)


## IA presupuestaria: mantiene el tesoro cerca de un objetivo (meses de gasto). Con superávit
## baja impuestos y, si ya están al mínimo, sube el gasto (educación, administración, social);
## con déficit hace lo contrario. Así el dinero recaudado vuelve a circular.
static func _ai_adjust(c: Dictionary, balance: float, expense: float) -> void:
	var b: Dictionary = c["budget"]
	var target := maxf(500.0, expense * 8.0)
	var treasury := float(c["treasury"])
	if balance < 0.0 or float(c["debt"]) > 0.0 or treasury < target * 0.25:
		if float(b["social"]) > 0.1:
			b["social"] = maxf(0.0, float(b["social"]) - 0.05)
		for k in ["tax_poor", "tax_middle", "tax_rich"]:
			b[k] = minf(0.5, float(b[k]) + 0.02)
	elif treasury > target and balance > 0.0:
		var lowered := false
		for k in ["tax_poor", "tax_middle", "tax_rich"]:
			if float(b[k]) > 0.06:
				b[k] = maxf(0.05, float(b[k]) - 0.02)
				lowered = true
		if not lowered or treasury > target * 3.0:
			for k in ["education", "administration", "social"]:
				b[k] = minf(1.0, float(b[k]) + 0.05)


## Ingresos y gastos del último mes (para la UI).
static func last_breakdown(c: Dictionary) -> Dictionary:
	return c.get("budget_last", new_acc())
