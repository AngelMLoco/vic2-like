# Segunda versión — Esquemas de datos

Todo el contenido vive en `data/victoria_mode/`. El motor no contiene listas de países,
provincias, bienes, etc. Los campos opcionales se marcan con `?`.

## Mapa (generado por `tools/map_import/build_world.py`)

| Archivo | Contenido |
|---|---|
| `map/provinces.png` | RGB 5632×2624, proyección Miller (80°N–56°S). `id = R + G*256`; `B` = distancia a la costa (px, 0–255). |
| `map/map.json` | `width`, `height`, `projection`, `land_count`, `sea_count`, `lake_count`, `first_sea_id`, `first_lake_id`, `source`. Ids de tierra: `1 … first_sea_id-1`. |
| `map/geometry.json` | Array: `{id, kind: land/sea/lake, center:[x,y], bbox:[x0,y0,x1,y1], area_px, area_km2, lonlat, neighbors:[ids]}` |
| `map/adjacencies.json` | Conexiones explícitas: `{a, b, type: sea_strait/land_crossing, name}` |

**Regenerar el mapa**: `python tools/map_import/build_world.py` (descarga Natural Earth a
`tools/map_import/.cache/`, ignorado por git). Las reglas están en `tools/map_import/world_rules.json`:
densidad de provincias por región, densidad de población, terreno climático, tablas de RGO,
estrechos y la asignación de propietarios/culturas (`assignments`, la primera regla que coincide
gana, evaluada sobre el centroide de cada provincia). **Regenerar sobrescribe `provinces/`, `states/`
y `map/`**: los cambios manuales en esos archivos se pierden; para contenido permanente
modificar las reglas o añadir overrides en `history/`.

## Provincias — `provinces/provinces.json`

```json
{"id":2858,"name":"Reims","state":312,"owner":"FRK","culture":"franca","religion":"aureliana",
 "terrain":"farmlands","rgo":"cattle","life_rating":37,"population":597580,"infrastructure":1}
```
`owner: ""` = territorio no colonizado. Al cargar se añaden `controller = owner`, `cores = [owner]`,
`fort`, `naval_base`, `occupation`, `coastal`, `pops`.

`provinces/sea_zones.json`: `{id, kind: sea/lake, name}`.

## Estados — `states/states.json`

`{id, name, provinces:[ids], modern_region}` — `modern_region` es solo referencia del generador.

## Países — `countries/countries.json` → `countries[]`

| Campo | Tipo | Notas |
|---|---|---|
| `tag` | string | 3 letras, único |
| `name`, `description` | string | |
| `color` | hex | color político |
| `flag` | `{pattern, colors[3]}` | patrones: tricolor_v/h, bicolor_h/v, nordic_cross, cross, saltire, canton, disc, diagonal, border, chevron |
| `capital` | int? | `null` → provincia propia más poblada |
| `primary_culture`, `accepted_cultures[]`, `religion` | ids | |
| `government` | id | `governments/governments.json` |
| `ruling_party` | `{name, ideology}` | |
| `civilized` | bool | las no civilizadas no pueden ser GP |
| `prestige`, `treasury`, `literacy` | número | |
| `technologies[]`, `reforms{}` | | fases 7–8 |
| `magic_branches` | `{technology, economy, military, politics}` | nº de ramas arcanas por área al activarse `GLOBAL_MAGIC_ACTIVATED` |

## Historia de inicio — `history/start_136.json`

`start_date`, `countries[tag] = {brigades, ships, factory_levels}`, `alliances[[a,b]]`,
`relations[[a,b,valor]]` (−200…200), `wars[{name, attackers[], defenders[], start}]`.

## Definiciones

| Archivo | Esquema |
|---|---|
| `cultures/cultures.json` | `groups[{id,name}]`, `cultures[{id,name,group,religion,color?}]` |
| `religions/religions.json` | `religions[{id,name,group,color}]` |
| `goods/goods.json` | `goods[{id,name,category: raw/industrial/consumer/luxury/military/fantasy, base_price, rgo: farm/mine/null, color, unlock_flag}]` |
| `factories/factories.json` | `factories[{id,name,inputs{good:qty},outputs{good:qty},workforce{craftsmen,clerks},build_cost{}}]` |
| `terrain/terrain.json` | `terrain[{id,name,color,movement_cost,defence,rgo_efficiency,supply_limit,attrition}]` |
| `pops/pop_types.json` | `pop_types[{id,name,strata: poor/middle/rich,color,literacy_mult,needs{life,everyday,luxury}}]`, `initial_distribution{civilized, civilized_developed, uncivilized, unowned}` |
| `governments/governments.json` | `governments[{id,name,elections,description}]` |
| `ideologies/ideologies.json` | `ideologies[{id,name,group,color}]` |

Para añadir un tipo de POP (p. ej. magos) basta con añadirlo a `pop_types.json`
(y, si se quiere que aparezca al inicio, a `initial_distribution`).

## Guardado (Modo B)

`user://victoria_mode/saves/<nombre>.json`:
`{save_version: 1, mode: "victoria_mode", header{name,country_tag,country_name,date_text,saved_at},
date, player_tag, flags, next_pop_id, countries{tag:{campos mutables}}, provinces{id:{owner,controller,
cores,occupation,fort,naval_base,infrastructure,life_rating,rgo,culture,religion,pops}}, state_factories{"sid:TAG":[…]}}`.
Si `save_version` no coincide y `_migrate()` no lo convierte, la carga se rechaza con un mensaje.

## Milestone 2

| Archivo | Esquema |
|---|---|
| `pops/pop_types.json` | `pop_types[{id,name,strata,color,literacy_mult,job,gov_wage,spend_fraction,vote_weight,issue_bias{issue:pos},needs{life,everyday,luxury: {good: qty por 10.000/mes}}}]`, `initial_distribution{civilized,uncivilized,unowned,slaves_if_allowed,factory_staff_headroom}`. `job`: rgo_farm, rgo_mine, rgo_any, factory_worker, factory_clerk, artisan, education, administration, military, leadership, rgo_owner, investor. |
| `pops/promotion.json` | `rules[{from,to,rate,conditions{…}}]` — condiciones: min/max_literacy, min/max_life, min/max_everyday, min_luxury, min/max_unemployment, min/max_cash_per_capita, min_consciousness, min/max_militancy, vacancy (factory_workers, factory_clerks, rgo, admin, clergy, military, officers), reform_min{}, reform_max{}, civilized, min/max_military_spending. |
| `economy/economy_rules.json` | constantes: valor RGO por 10.000 trabajadores, parte del propietario, valor por nivel de fábrica y por 10.000 artesanos, multiplicador salarial, reinversión, cierre, límites y velocidad de precios, intereses, construcción, bienes de la reserva militar y políticas que permiten inversión privada / construcción estatal / subvenciones. |
| `factories/factories.json` | además: `requires_tech`, `artisan` (los artesanos pueden fabricarlo). inputs/outputs = una unidad de receta; el número de recetas al mes sale de `factory_value_per_level` y los precios base. |
| `politics/issues.json` | `issues[{id,name,positions[{id,name}]}]`, `conditional[{if{condiciones de POP},issue,position}]` |
| `politics/reforms.json` | `reforms[{id,name,type: political/social,issue,default,levels[{id,name,effects{}}]}]`, `movement_names{}`, `cooldown_months`. Efectos usados: vote_rule, consciousness_growth, militancy_growth, ideology_drift, factory_wage, socialist_drift, pop_growth, social_cost, literacy_growth, pension, unemployment_benefit, worker_militancy, factory_throughput. |
| `politics/party_templates.json` | `templates[{ideology,name,requires_reform{},policies{economic_policy,trade_policy,religious_policy,citizenship_policy,war_policy}}]` → cada nación recibe «<nombre> de <nación>». Un país puede definir `custom_parties`. |
| `governments/governments.json` | además: `election_interval_months`, `appoint_ruling_party`, `allowed_parties[]`, `can_reform`, `reform_caps{reforma: nivel máx.}`. |
| `ideologies/ideologies.json` | además: `strata_affinity{poor,middle,rich}`, `reform_support{political,social}` (−1…1), `issues{issue: posición}`. |
| `technologies/technologies.json` | `categories[]`, `technologies[{id,name,category,tier,cost,prerequisites[],effects{},unlocks_factories[]}]` |
| `technologies/inventions.json` | `inventions[{id,name,technology,chance (mensual),conditions{min_literacy,min_prestige,civilized,has_tech,flag},effects{}}]` |
| `countries/countries.json` | `reforms{}` = niveles iniciales distintos del valor por defecto. |

Guardado: `save_version` = 2. Añade economía (mercado, fábricas con stock y caja, RGO), presupuesto, deuda, banco,
proyectos, tecnologías, inventos, investigación, partidos, elecciones, cámara alta, movimientos y registro.
Las partidas v1 se rechazan con un mensaje claro.

## Milestone 3

| Archivo | Esquema |
|---|---|
| `military/unit_types.json` | `manpower`, `base_combat_width`, `units[{id,name,attack,defence,organisation,morale,discipline,recon,siege,speed,width,support,supply{good: qty por brigada y mes},requires_tech,build_cost{}}]` |
| `military/ship_types.json` | `ships[{id,name,attack,defence,hull,speed,range,transport,supply{},requires_tech,build_cost{},days}]` |
| `military/leader_traits.json` | `personalities[]`, `backgrounds[]` (modificadores attack/defence/morale/organisation/speed/recon), `names[]`, `surnames[]`, `leadership_cost_general/admiral` |
| `war/casus_belli.json` | `casus_belli[{id,name,scope: state/country/province,warscore_cost,infamy,prestige,justify_months,duration_months,conditions[],peace_effect}]`, `max_infamy`, `infamy_decay_per_month`, `truce_months`, `justify_discovery_chance`. Condiciones: target_not_gp, target_gp, actor_gp, target_neighbor, target_has_actor_core, target_in_other_sphere, target_uncivilized, actor_civilized. Efectos: annex_state, conquest, restore_core, humiliate, cut_down, reparations, release_nation, liberate_country, place_in_sphere, free_from_sphere. |
| `diplomacy/diplomacy_rules.json` | puntos diplomáticos, `costs{acción: puntos}`, `relation_change`, `relation_drift_per_month`, `alliance_min_relations`, `influence{base_per_month, prestige_factor, max_targets, points_cap, costs{}, discredit_months, ban_months, gp_grace_months, opinion_levels[], opinion_names{}}` |
| `rebels/rebel_types.json` | `types[{id,name,from_reforms[],demand: raise_reform/lower_reform/change_ruling_ideology,ideology,color}]`; umbrales `min_radicalism`, `min_organisation`, `min_supporter_militancy`, `spawn_share`, `max_brigades`, `victory_months`, `victory_province_share` |

Entidades nuevas del estado (serializadas en el guardado v3, bloque `military`):

* `armies{id: {id,country,name,province,brigades[],leader,morale,path[],move_progress,retreating,dig_in,supply,battle,embarked,rebel_faction}}`
* `brigades{id: {id,type,strength,organisation,experience,source_pop_id,source_province_id,army}}`
* `leaders{id: {id,country,kind,name,traits[],attack,defence,morale,organisation,speed,recon,army,fleet}}`
* `fleets{id: {id,country,name,location,ships[{id,type,hull,organisation}],admiral,path[],mission,transported_armies[]}}`
* `wars{id: {id,name,start,attackers[],defenders[],primary_attacker,primary_defender,war_goals[{id,type,actor,target,state_id}],battle_ws,occupation_ws,blockade_ws,ticking_ws,total_ws,offer}}`
* `battles`, `casus_belli[{id,owner,target,type,state_id,expires}]`, `justifications[{owner,target,type,state_id,progress,months,discovered}]`
* `rebel_factions{id: {id,type,country,movement,demand,supporting_pops[],strength,organisation,risen,controlled_provinces[],armies[],months_holding}}`

País: `diplo_points, military_access[], guarantees[], truces{tag: mes}, wars[ids], influence{target: {points,opinion,priority,banned_until,discredited_until}}, sphere_leader, leadership, casualties, war_exhaustion, infamy, reparations[], ship_queue[], blockade_ratio`.
Provincia: `controller` (puede ser `REB`), `occupation`, `occupation_by`, `blockaded_by`, `rebel_faction`.

`save_version` = 3; las partidas v2 se rechazan con un mensaje.

## M3.2 — Almacén de POPs y guardado v4

Los POPs ya no son diccionarios dentro de cada provincia. Viven en `VPopStore` (`gs.pops`), con un array por
campo e índice = slot. Cada provincia guarda la lista ordenada de sus slots en `p["pop_slots"]`. Los ids estables
(`id`) se usan para los enlaces externos: `brigade.source_pop_id` y `rebel_faction.supporting_pops`.

| Campo | Tipo | Notas |
|---|---|---|
| `id`, `province`, `type_id`, `culture_id`, `religion_id`, `size`, `employer`, `unemployed_months`, `migration_target` | `Array[int]` | `id = -1` en slots libres (`free_list`) |
| `cash`, `bank`, `income`, `income_acc`, `employment`, `literacy`, `consciousness`, `militancy`, `life`, `everyday`, `luxury`, `movement_push` | `Array[float]` | |
| `ideology` | `Array[float]` plano | `slot * n_ideo + k`, en el orden de `ideologies.json` |
| `issues` | `Array` de diccionarios | compartidos y de solo lectura por (ideología dominante, tipo, reglas cumplidas) |
| `product`, `promotion_target` | `Array[String]` | |
| `brigades` | `Array` (`null` o lista de ids de brigada) | Soldier POPs |

Tablas de ida y vuelta: `type_names`/`type_index`, `culture_names`, `religion_names`, `ideo_names`, `employer_names`
(empleadores internados: "", "rgo", "estado", "inversión", "fábrica", "rgo_owner", "artisan:<producto>").
`id_to_slot` resuelve también los ids de POPs fusionados, que apuntan al POP que los absorbió.

`get_pop_details(slot)` devuelve un diccionario temporal con los campos clásicos (`type`, `size`, `culture`,
`needs_satisfaction`, `ideology`, `issues`…) para la UI y la depuración.

**Guardado:** `save_version` = 4. La clave `pops` contiene columnas (`id[]`, `province[]`, `type_id[]`, `size[]`,
`cash[]`…, `ideology[]` plana), las tablas de nombres, `issue_table` + `issue_idx` (un diccionario por
combinación distinta), `brigades {índice: [ids]}`, `aliases {id fusionado: id destino}`, `next_id` y `stats`.
Las provincias ya no guardan POPs. Las partidas v3 se rechazan con un mensaje.

`economy_rules.json` añade:
* `militancy_relaxation` (0,01): fracción de la militancia que se disipa cada mes.
* `unemployment_relief_factor` (2,0): cuánto reduce el subsidio de paro (reforma × presupuesto social) la
  militancia causada por el paro, con un máximo del 80 %.

## Milestone 4 — Eventos, decisiones y magia

Añadir un evento, una decisión, una tecnología, un bien o una fábrica mágica = añadir JSON; no hay que tocar el
código. El cargador valida todo y muestra errores claros.

### Evento — `events/*.json`, `magic/events/*.json` → `events[]`

```json
{"id": "emergent.food_crisis", "scope": "country", "type": "normal", "cadence": "monthly",
 "title": "…", "desc": "…", "art": "famine",
 "tags": ["FRK"], "requires_flag": "GLOBAL_MAGIC_ACTIVATED", "target": "lowest_relation_neighbor",
 "province_candidates": "capital",
 "trigger": {"avg_life_below": 0.62, "good_price": {"grain": 1.35}},
 "mtth": {"months": 18, "modifiers": [{"factor": 0.5, "militancy": 2.5}]}, "chance": 0.3,
 "once": false, "cooldown": 36, "important": true,
 "immediate": {…efectos…},
 "options": [{"name": "…", "trigger": {…}, "effects": {…},
   "ai_weight": {"base": 10, "modifiers": [{"factor": 0.3, "treasury_below": 500}]},
   "follow_up": {"id": "emergent.bread_riots", "months": 2}}]}
```

* `scope`: `global` | `country` | `state` | `province`. Los de provincia exigen `province_candidates`:
  `capital` | `owned` | `magic` | `occupied` | `coastal`.
* `type`: `major` (ventana destacada, fuera del presupuesto) | `normal` | `notification` (sin ventana) | `hidden`.
* `cadence`: `daily` | `monthly` (por defecto) | `quarterly` | `yearly` | `on_action` (+ `on_action`: nombre del
  gancho) | `follow_up` (solo como continuación o con `trigger_event`).
* `target`: `lowest_relation_neighbor`, `highest_relation_neighbor`, `strongest_neighbor`, `weakest_neighbor`,
  `random_neighbor`, `sphere_leader`, `war_enemy`, `from`.
* Sin `mtth` ni `chance`, el evento ocurre en cuanto se cumple el trigger.

### Condiciones (eventos y decisiones)

* **Lógica:** `and`, `or` ([…]), `not`, `target` {…} (en la nación objetivo), `owner` {…}, `any_neighbor` {…},
  `count_countries` {min, where}.
* **Numéricas:** `campo: x` → campo ≥ x; `campo_below: x` → campo < x.
  * De nación: `prestige`, `military_score`, `industry_score`, `treasury`, `debt`, `literacy`, `militancy`,
    `consciousness`, `unemployment`, `avg_life`, `avg_everyday`, `population`, `war_exhaustion`, `infamy`,
    `factory_count`, `research_points`, `wars`, `brigades`, `provinces`, `magi`.
  * De provincia: `province_population`, `province_unemployment`, `province_militancy`, `life_rating`, `fort`,
    `naval_base`, `infrastructure`, `magic_potential`, `province_life`.
  * Globales: `number_of_wars`, `world_literacy`, `world_militancy`, `world_avg_life`, `great_powers_at_war`.
* **De nación:**
  * fecha y banderas: `year`, `year_below`, `month`, `flag`/`not_flag` (globales), `country_flag`/`not_country_flag`;
  * identidad y rango: `tag`, `civilized`, `great_power`, `secondary_power`, `rank_above`, `rank_below`;
  * gobierno: `government`, `ruling_ideology`, `reform_min`/`reform_max` {reforma: nivel};
  * tecnología: `has_technology`, `has_invention`;
  * guerra y diplomacia: `at_war`, `has_sphere`, `in_sphere`, `has_target`, `target_relation`/`_below`,
    `owns_province`, `owns_state`, `controls_province`, `controls_state`, `has_core`;
  * economía: `factory_type_count` {tipo: n}, `good_price`/`good_price_below` {bien: proporción del precio base},
    `good_shortage` {bien: llenado mínimo}, `good_available`;
  * política y rebeldes: `rebel_risk`, `rebel_faction_exists`, `movement_support` {reforma: apoyo};
  * magia: `magic_branch` {rama: nivel}, `magic_any_branch`;
  * otros: `variable`/`variable_below` {nombre: valor}, `pop_type_size` {tipo: personas}, `is_player`,
    `has_modifier`.
* **De provincia:** `owner_is`, `controller_is` (admiten `self`, `target`, `from`), `terrain`, `coastal`, `rgo`,
  `culture`, `religion`, `occupied`, `blockaded`, `has_magic_deposit`, `state`, `is_capital`, `province_flag`,
  `not_province_flag`.

### Efectos (eventos y decisiones)

* **Dinero, prestigio e infamia:** `add_treasury`, `add_treasury_ratio` (fracción del tesoro), `add_prestige`,
  `add_infamy`.
* **POPs:** `add_militancy`/`add_consciousness` (número o {value, strata}), `add_population`/`kill_population`
  (fracción), `convert_pops` {from, to, share, max}.
* **Política y presupuesto:** `change_reform` {reforma: ±1}, `change_budget` {slider: ±}.
* **Diplomacia:** `change_relation` (con el objetivo).
* **Modificadores:** `add_country_modifier`/`add_province_modifier` ({id, months} o una lista),
  `remove_country_modifier`.
* **Banderas y variables:** `set_flag`/`clear_flag`, `set_country_flag`/`clear_country_flag`,
  `set_province_flag`/`clear_province_flag` (admiten listas), `set_variable`/`change_variable`.
* **Provincias:** `add_core`/`remove_core`, `change_owner`/`change_controller` (`gs.change_owner`,
  `VWarSystem.set_controller`), `change_rgo`.
* **Tecnología:** `add_technology`, `add_invention`, `start_research`, `add_research_points`.
* **Economía:** `add_good_stockpile`, `build_factory` {type}, `close_factory` {type|any}.
* **Guerra y rebeldes:** `spawn_rebels` {movement}, `create_casus_belli`/`start_war` {cb, state} (con el
  objetivo), `add_war_exhaustion`.
* **Esferas:** `add_influence`, `add_to_sphere`, `remove_from_sphere`.
* **Encadenar:** `trigger_event` {id, days}.
* **Magia:** `activate_magic`, `add_magic_deposit`, `discover_magic_deposit`.
* **Otros:** `log`.
* **Cambios de ámbito:** `target` {…}, `owner` {…}, `capital` {…},
  `every_owned_province`/`random_owned_province` {limit, effects}.

### Modificadores — `events/modifiers.json` → `modifiers[{id, name, effects}]`

Los de nación usan las claves de VModifiers. Claves nuevas que leen los sistemas:
* `mana_extraction`: producción de los yacimientos.
* `mage_emergence`: aparición de magos.
* `battle_magic`: el resolver de batalla.

Los de provincia admiten `rgo_efficiency`, `rgo_size`, `pop_growth`, `militancy`, `literacy_growth` y
`consciousness_growth`.

### Decisión — `decisions/*.json`, `magic/decisions/*.json` → `decisions[]`

`{id, name, desc, category (industrial|political|diplomatic|military|magic), tags, requires_flag, visible {cond},
available {cond}, cost {treasury, prestige, research}, effects, ai_weight (probabilidad por trimestre: número o
{base, modifiers}), cooldown (meses), once}`

### Magia

* `magic/prototype_branches.json`: perfiles PROTOTYPE de `magic_branches` por nación y `rules`.
  * Yacimientos: `deposit_good`, `deposit_chance`, `deposit_output`, `terrain_weight`.
  * Magos: `mage_type`, `mage_sources`, `mage_min_literacy`, `mage_rate`, `mage_min_branch`.
* `magic/technologies.json`: `categories`, `technologies[]` (con `magic_branch`, `min_level`, `requires_flag`,
  `unlocks_factories`) e `inventions[]`.
* Bienes `fantasy` en `goods.json` (`unlock_flag: GLOBAL_MAGIC_ACTIVATED`), fábricas mágicas en
  `factories.json` (`requires_tech`), el tipo de POP `magi` en `pop_types.json` y la unidad `arcane_support`
  en `unit_types.json`.
* Provincia: `magic {potential, deposit}`.

**Guardado:** `save_version` = 5 (añade `events` y `magic` de provincia); las partidas v4 se rechazan.
