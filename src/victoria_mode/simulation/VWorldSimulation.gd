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
	VProfiler.end(gs, "daily_tick", t0)


func process_bucket(b: int) -> void:
	var t0 := VProfiler.begin()
	for key in _bucket_instances[b]:
		var si: Dictionary = gs.state_instances.get(key, {})
		if not si.is_empty():
			VProductionSystem.process_state_instance(gs, si)
	for id in _bucket_provinces[b]:
		VProductionSystem.process_province(gs, id)
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
	VPopulationSystem.flush_demand(gs)
	var tm := VProfiler.begin()
	VMarketSystem.clear_month(gs)
	if gs.month_index <= 12 and gs.flags.get("scenario_warmup", true):
		VProductionSystem.warmup_recalibrate(gs)
	VProfiler.end(gs, "market", tm)
	var tc := VProfiler.begin()
	VPopulationSystem.refresh_country_caches(gs)
	VProfiler.end(gs, "month_caches", tc)
	var tb := VProfiler.begin()
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var is_player := tag == gs.player_tag
		VBudgetSystem.settle_month(gs, tag, is_player)
		VTechnologySystem.monthly(gs, tag, is_player)
		VPoliticsSystem.monthly(gs, tag, is_player)
		VProductionSystem.monthly_country(gs, tag, is_player)
	VProfiler.end(gs, "country_month", tb)
	if gs.flags.get("money_audit", false) or gs.month_index % 3 == 0:
		var ta := VProfiler.begin()
		VMoney.audit(gs)
		VProfiler.end(gs, "money_audit", ta)
	var tt := VProfiler.begin()
	VMobilitySystem.monthly_targets(gs)
	VRankingSystem.recalculate(gs)
	VPopulationSystem.prepare_month(gs)
	VProfiler.end(gs, "month_targets_rank", tt)
	VProfiler.end(gs, "monthly_tick", t0)


## Simulación rápida sin interfaz (pruebas y balance): avanza 'days' días.
func run_days(days: int, clock_date: VDate = null) -> void:
	var date: VDate = clock_date if clock_date != null else gs.date
	for i in days:
		var new_month := date.advance_day()
		if new_month:
			on_month()
		on_day()
