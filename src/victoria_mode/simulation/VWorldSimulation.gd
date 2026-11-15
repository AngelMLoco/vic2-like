class_name VWorldSimulation
extends RefCounted
## Orquestador de la simulación. No contiene reglas: decide el orden y el reparto temporal.
##
## Rendimiento: el trabajo mensual por provincia/POP NO se hace en un único tick. Las provincias
## se reparten en BUCKETS cubos (id % BUCKETS) y cada día 1..BUCKETS del mes se procesa un cubo:
##   fábricas de las particiones de estado cuyo id clave cae en el cubo → RGO/artesanos/empleo estatal
##   → necesidades y consecuencias de los POPs → movilidad y migración.
## Cada POP se procesa exactamente una vez al mes. Al cerrar el mes (on_month):
##   demanda agregada → casación del mercado (precios, llenado, aranceles) → presupuesto
##   → tecnología → política → inversión → destinos de migración → agregados → ranking
##   → cachés de precios para el mes siguiente.
## Nada de esto ocurre por frame: solo en ticks del reloj (VTimeController).

const BUCKETS := 28

var gs: VGameState
var _bucket_provinces: Array = []  # bucket -> [province ids]
var _bucket_instances: Array = []  # bucket -> [state instance keys]


func _init(state: VGameState) -> void:
	gs = state
	_build_buckets()
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		if not c.has("acc_mobility"):
			c["acc_mobility"] = {}
	VProductionSystem.derive_rates(gs)
	VPopulationSystem.refresh_country_caches(gs)
	VPopulationSystem.prepare_month(gs)
	VMobilitySystem.monthly_targets(gs)
	gs.ownership_changed.connect(func(_ids): territory_changed())


func _build_buckets() -> void:
	_bucket_provinces = []
	_bucket_instances = []
	for i in BUCKETS:
		_bucket_provinces.append([])
		_bucket_instances.append([])
	for id in range(1, gs.first_sea_id):
		_bucket_provinces[id % BUCKETS].append(id)
	for key in gs.state_instances:
		var ids: Array = gs.state_instances[key]["provinces"]
		var k: int = ids.min() if not ids.is_empty() else 0
		_bucket_instances[k % BUCKETS].append(key)


## Llamar tras cambios de propiedad (las instancias de estado cambian).
func territory_changed() -> void:
	_build_buckets()


func on_day() -> void:
	var t0 := VProfiler.begin()
	var d := gs.date.day
	if d >= 1 and d <= BUCKETS:
		process_bucket(d - 1)
	var tm := VProfiler.begin()
	military_day()
	VProfiler.end(gs, "military_day", tm)
	VProfiler.end(gs, "daily_tick", t0)


## Capa militar diaria: movimiento, combate, suministro, asedios, warscore, armada e IA.
func military_day() -> void:
	var t := VProfiler.begin()
	VArmySystem.daily_movement(gs)
	VProfiler.end(gs, "army_movement", t)
	t = VProfiler.begin()
	VCombatSystem.daily(gs)
	VProfiler.end(gs, "combat", t)
	t = VProfiler.begin()
	VSupplySystem.daily(gs)
	VProfiler.end(gs, "supply", t)
	t = VProfiler.begin()
	VArmySystem.daily_reinforce(gs)
	VProfiler.end(gs, "reinforcement", t)
	VWarSystem.daily(gs)  # mide «sieges» y «war_score» por dentro
	t = VProfiler.begin()
	VNavySystem.daily(gs)
	VProfiler.end(gs, "navy", t)
	VMilitaryAI.daily(gs)  # mide «military_ai_land» y «military_ai_navy» por dentro


func process_bucket(b: int) -> void:
	var t0 := VProfiler.begin()
	for key in _bucket_instances[b]:
		var si: Dictionary = gs.state_instances.get(key, {})
		if not si.is_empty():
			VProductionSystem.process_state_instance(gs, si)
	VProfiler.end(gs, "production_factories", t0)
	var tp := VProfiler.begin()
	for id in _bucket_provinces[b]:
		VProductionSystem.process_province(gs, id)
	VProfiler.end(gs, "production_provinces", tp)
	VProfiler.end(gs, "production", t0)
	var t1 := VProfiler.begin()
	for id in _bucket_provinces[b]:
		VPopulationSystem.process_province(gs, id)
	VProfiler.end(gs, "population", t1)
	var t2 := VProfiler.begin()
	for id in _bucket_provinces[b]:
		VMobilitySystem.process_province(gs, id)
	VProfiler.end(gs, "mobility", t2)


func on_month() -> void:
	var t0 := VProfiler.begin()
	gs.month_index += 1
	var tf := VProfiler.begin()
	VPopulationSystem.flush_demand(gs)
	VProfiler.end(gs, "m_population_flush", tf)
	var tm := VProfiler.begin()
	VMarketSystem.clear_month(gs)
	if gs.month_index <= 12 and gs.flags.get("scenario_warmup", true):
		VProductionSystem.warmup_recalibrate(gs)
	VProfiler.end(gs, "m_market", tm)
	var tc := VProfiler.begin()
	VPopulationSystem.refresh_country_caches(gs)
	VProfiler.end(gs, "m_population_caches", tc)
	var tb := VProfiler.begin()
	var us := [0, 0, 0, 0]
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var is_player := tag == gs.player_tag
		var t1 := Time.get_ticks_usec()
		VBudgetSystem.settle_month(gs, tag, is_player)
		var t2 := Time.get_ticks_usec()
		VTechnologySystem.monthly(gs, tag, is_player)
		var t3 := Time.get_ticks_usec()
		VPoliticsSystem.monthly(gs, tag, is_player)
		var t4 := Time.get_ticks_usec()
		VProductionSystem.monthly_country(gs, tag, is_player)
		var t5 := Time.get_ticks_usec()
		us[0] += t2 - t1
		us[1] += t3 - t2
		us[2] += t4 - t3
		us[3] += t5 - t4
	VProfiler.add(gs, "m_budget", us[0] / 1000.0)
	VProfiler.add(gs, "m_technology", us[1] / 1000.0)
	VProfiler.add(gs, "m_politics", us[2] / 1000.0)
	VProfiler.add(gs, "m_production_invest", us[3] / 1000.0)
	VProfiler.end(gs, "m_country_total", tb)
	var tw := VProfiler.begin()
	VDiplomacySystem.monthly(gs)
	VDiplomacySystem.ai_monthly(gs)
	VProfiler.end(gs, "m_diplomacy", tw)
	tw = VProfiler.begin()
	VInfluenceSystem.monthly(gs)
	VInfluenceSystem.ai_monthly(gs)
	VProfiler.end(gs, "m_influence", tw)
	tw = VProfiler.begin()
	VWarSystem.monthly(gs)
	VWarSystem.ai_monthly(gs)
	VProfiler.end(gs, "m_war", tw)
	tw = VProfiler.begin()
	VLeaderSystem.monthly(gs)
	VProfiler.end(gs, "m_leaders", tw)
	tw = VProfiler.begin()
	VRebelSystem.monthly(gs)
	VProfiler.end(gs, "m_rebels", tw)
	tw = VProfiler.begin()
	VArmySystem.update_counts(gs)
	VNavySystem.update_counts(gs)
	VProfiler.end(gs, "m_unit_counts", tw)
	if gs.flags.get("money_audit", false) or gs.month_index % 3 == 0:
		var ta := VProfiler.begin()
		VMoney.audit(gs)
		VProfiler.end(gs, "m_money_audit", ta)
	var tt := VProfiler.begin()
	VMobilitySystem.monthly_targets(gs)
	VProfiler.end(gs, "m_mobility_targets", tt)
	tt = VProfiler.begin()
	VRankingSystem.recalculate(gs)
	VProfiler.end(gs, "m_ranking", tt)
	tt = VProfiler.begin()
	VPopulationSystem.prepare_month(gs)
	VProfiler.end(gs, "m_population_prepare", tt)
	VProfiler.end(gs, "monthly_tick", t0)


## Simulación rápida sin interfaz (pruebas y balance): avanza 'days' días.
func run_days(days: int, clock_date: VDate = null) -> void:
	var date: VDate = clock_date if clock_date != null else gs.date
	for i in days:
		var new_month := date.advance_day()
		if new_month:
			on_month()
		on_day()
