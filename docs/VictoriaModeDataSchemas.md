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

### Evento — `content/<paquete>/events/*.json` → `events[]` (M4; rutas y espacios de nombres de M5)

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

## Milestone 5 — Paquetes de contenido, escenarios, magia y crónica

### Escenarios — `scenarios/scenarios.json`

```json
{"default": "prototype_136",
 "scenarios": [{"id": "prototype_136", "name": "Prototipo — Año 136", "era": "prototype",
   "history": "history/start_136.json", "content_packs": ["core", "prototype"]}],
 "eras": [{"id": "prototype", "name": "Prototipo"}]}
```

El archivo de historia admite (todo opcional):

* `start_date`, `flags`;
* `provinces` {id: owner, controller, cores};
* `relations`, `alliances`, `rivals`, `wars`;
* `countries` {TAG: government, capital, literacy, prestige, treasury, brigades, ships, factory_levels,
  technologies, inventions, reforms, flags, variables, modifiers, magic_branches}.

Ejemplo completo en `docs/LoreBibleSchema.md`.

### Paquetes — `content/<paquete>/`

| Archivo | Contenido |
|---|---|
| `pack.json` | id, name, description, requires |
| `events/*.json` | `{"events": [...]}` |
| `decisions/*.json` | `{"decisions": [...]}` |
| `modifiers.json` | `{"modifiers": [...]}` |
| `chronicle.json` | `{"templates": {on_action: {"cat", "text", "text_target", "important"}}}` |
| `art_manifest.json` | `{"style": {...}, "categories": [{"art_key", "title", "description", "composition", "location", "characters", "mood", "magic_visibility", "events"}]}` |
| `magic_branches.json` | `{"branches": {TAG: {rama: nivel | {"level", "paths"}}}}` |
| `lore/*.json` | Biblia de lore (`docs/LoreBibleSchema.md`) |

`content/packs.json` → `load_order` es el orden por defecto si el escenario no declara paquetes.

### Eventos: campos nuevos

* `id` con espacio de nombres: `core.<economy|politics|society|religion|war|diplomacy|migration|technology>.*`,
  `magic.<world|social|economy|politics|military>.*`, `country.<tag>.*` o `region.<id>.*`.
* `category` (opcional): `politics` | `war` | `economy` | `diplomacy` | `society` | `magic`. Si falta, sale
  del espacio de nombres.
* `chronicle` (evento u opción): texto narrativo para la crónica. Marcadores: `{country}`, `{target}`, `{war}`,
  `{province}`, `{reform}`, `{level}`, `{tech}` y `{year}`.
* `art`: debe ser una categoría del manifiesto de arte.
* Nuevo on_action `mage_brain_drain` (tag = origen, target = destino, amount). El contexto de `war_ended`
  incluye `result`, `goals`, `war_months`, `war_name` y `primary`; el de `battle_won` / `battle_lost`,
  `losses` (del enemigo) y `own_losses`.

### Condiciones nuevas

| Condición | Valor | Significado |
|---|---|---|
| `battle_losses`, `own_losses`, `peace_goals` (y `_below`) | número | Contexto de batalla o de paz |
| `war_result` | `victory` / `defeat` / `white_peace` | Resultado de la paz |
| `capital_occupied` | bool | Capital en manos de otro |
| `magic_regulation` | [niveles] | Nivel actual de la reforma |
| `religion_magic_attitude` | [actitudes] | Actitud mágica de la religión de Estado |
| `magic_tradition` | [tradiciones] | Tradición mágica de la cultura principal |
| `magic_path` | {rama: escuela} | La rama declara esa senda |
| `is_rival` | bool | El objetivo es rival declarado |
| `ruling_ideology` | ideología o lista de ideologías | Ideología del partido gobernante |
| `magi_share`, `magi_unemployment`, `magi_target_ratio` | número | Magos frente a población, paro de magos, magos frente a capacidad |
| `mage_emigration`, `mage_immigration` | número | Magos emigrados o inmigrados, media anual |
| `arcane_academies`, `arcane_deposits`, `magic_factories` | número | Academias, yacimientos y fábricas mágicas |
| `immigration`, `emigration` | número | Del último mes |
| `war_months` | número | Duración de la guerra más larga |

### Efectos nuevos

* `set_magic_regulation`: id de nivel; decreto sin pasar por la cámara.
* `mage_emigration`: fracción de magos que emigra ya.
* `chronicle`: `"texto"` o `{"text", "cat", "important"}`.
* `add_militancy` / `add_consciousness`: aceptan `pop_type` (tipo o lista de tipos) y son listables (`[{…}, {…}]`).

### Magia — `magic/magic_rules.json` → `rules.mage_model`

| Grupo | Claves | Uso |
|---|---|---|
| Capacidad | `base_share`, `no_branch_factor`, `branch_base`, `branch_per_level` | Capacidad social y factor por ramas |
| Alfabetización | `literacy_ref`, `literacy_min`, `literacy_max` | Factor de alfabetización y sus límites |
| Academias | `academy_capacity`, `academy_promotion`, `academy_posts`, `academy_research` | Efectos de cada academia |
| Promoción | `convergence`, `min_promotion`, `max_pop_share_per_month`, `jobs_weight` | Ritmo hacia el objetivo y peso del paro |
| Exceso | `demotion_rate`, `demote_to`, `excess_tolerance` | Degradación por encima del objetivo |
| Migración | `emigration_rate`, `emigration_push_min`, `destinations` | Fuga de cerebros |
| Salarios | `factory_wage_multiplier`, `practice_share`, `practice_pay` | Fábricas y práctica privada |
| Fe y cultura | `religion_attitudes` {actitud: {promotion, tension}}, `culture_traditions` {tradición: factor}, `tension_magi_share_ref` | Modulación por religión y cultura |

`mage_sources`, `mage_min_literacy` y `mage_min_branch` siguen en `rules`.

**Modificadores leídos por el modelo:**

* `mage_capacity`, `mage_promotion`, `mage_attraction`, `mage_practice`;
* `mage_state_posts` (fracción de la población), `mage_military_posts` (fracción de los soldados);
* `magic_research`, `magic_factory_efficiency`, `magi_militancy`, `religious_tension`.

**Otros datos:**

* `factories.json`: `workforce.magi` (magos por nivel).
* `pop_types.json`: magos con oficio `arcane`.
* `religions.json` → `magic_attitude`; `cultures.json` → `groups[].magic_tradition` (o por cultura).
* `magic/magic_schools.json` → `schools: [{id, branch, name, min_level, effects}]` (vacío hasta el lore).

### Reforma `magic_regulation` — `politics/reforms.json`

`type: "magic"`, `issue: "magic_policy"`, `requires_flag: "GLOBAL_MAGIC_ACTIVATED"`, `movement: false`. La
postura de cada ideología está en `ideologies.json` → `issues.magic_policy` (id de nivel).

### Guardado v6

Ids de eventos con espacio de nombres, reforma `magic_regulation`, `magic_stats` y `rivals` por nación, y
escenario y paquetes en la cabecera. Las partidas v5 se rechazan.

## M5.5 — Economía de largo plazo

### `economy/economy_rules.json`

* `investment` (`VInvestmentSystem`):

  | Grupo | Claves | Uso |
  |---|---|---|
  | Capacidad privada | `levels_per_slot`, `capitalists_per_slot`, `capital_per_slot`, `max_private` | Proyectos simultáneos de capitalistas |
  | Inicios | `slots_per_extra_start` (inicios por mes), `min_starts_year`, `max_growth_year` (techo anual = max(mínimo, niveles × crecimiento)) | Ritmo de nuevos proyectos |
  | Estado | `gov_levels_per_slot`, `gov_treasury_per_slot`, `max_government` | Capacidad estatal |
  | Programa industrial | `gov_unemployment_threshold`, `gov_reserve_months`, `gov_reserve_months_crisis` | Respuesta del Estado al paro |
  | Rural | `provinces_per_rgo_slot`, `max_rgo` | Capacidad de desarrollo rural |
  | Mano de obra | `states_considered`, `min_labour_pool`, `rural_labour_share`, `literate_rural_share` | Trabajadores disponibles por estado |
  | Puntuación | `weight_unemployment`, `weight_shortage`, `weight_urbanisation`, `magic_unemployment_bonus` | Pesos del score de inversión |
  | Subvenciones | `subsidy_reserve_months`, `subsidy_months`, `subsidy_margin_tolerance` | IA de subvenciones temporales |

* `state_factory_slots`: `base`, `per_infrastructure`, `per_urbanisation`, `max`. Plazas de fábrica por
  partición de estado.
* `rgo_development`: `size_per_level`, `efficiency_per_level`, `max_base`, `max_per_infrastructure`,
  `min_rural_unemployment`, `min_profit_ratio`, `min_price_ratio`, `aristocrat_capital_ratio`, `cost_goods`
  {bien: cantidad por cada `cost_size_unit` de tamaño del RGO}.
* Retirados: `investment_cooldown_months` y `factories_per_parallel_project`.

### Modificadores nuevos (tecnologías, reformas, eventos)

* `investment_capacity`: multiplica la capacidad privada.
* `state_factory_slots`: plazas de fábrica adicionales por estado.
* `rgo_development_max`: niveles adicionales de mejora rural.

Se asignan, entre otras, a molinos de agua, química agrícola, conservación de alimentos, talleres mecánicos,
química industrial, siderurgia y regulación del mercado.

### Estado nuevo

* `province.rgo_dev`: nivel de mejoras rurales. Se guarda; si falta vale 0.
* Proyectos: `kind` (`factory` | `rgo`), `prov` (si es rural), `investor` (`capitalists` | `government` |
  `aristocrats`) y `stalled_months`.
* Derivados, no guardados: `_inv_capacity`, `_inv_reasons`, `_inv_stats`, `_factory_levels`,
  `_capital_pool`, `_starts_year` y `si._urban`.

El guardado sigue siendo **v6**: todo lo nuevo tiene valores por defecto compatibles.

### Fábricas y magia

* `arcane_machine_works` (componentes encantados + acero → maquinaria).
* `alchemical_fertilizer_works` (reactivos + azufre → fertilizante).
* `magic_rules.mage_model.academy_reagents`: reactivos que consume cada academia al mes.

## M5.6 — Demanda, precios y madurez política

### `economy/economy_rules.json`

| Clave | Contenido | Uso |
|---|---|---|
| `engel` | `life`, `everyday`, `luxury` (elasticidad por nivel), `k` (saturación), `wealth_weight` | Consumo extra = elasticidad × (1 − e^(−k·(recursos/coste − 1))); recursos = renta del mes + `wealth_weight` × (efectivo + depósitos). `wealth_weight` vale 0 |
| `rgo_utilisation` | `low_price`, `oversupply`, `recover_price`, `down`, `up`, `min` | Utilización del RGO (0,6…1) según precio relativo de 12 meses y oferta/demanda mundial |
| `political_outlet` | `reforms` {reforma: peso}, `repression_factor`, `outlet_factor`, `outlet_cooling` | Cauce político (0…1): frena el radicalismo y lo enfría |
| `state_jobs` | `clergy_base`, `clergy_per_education`, `clergy_literacy_saturation`, `admin_base`, `admin_per_slider`, `reserve_ratio`, `base_reserve`, `reserve_share_per_slider`, `war_multiplier`, `officer_ratio`, `excess_tolerance` | Plazas funcionales de clero, burócratas, soldados y oficiales |
| `settle_purchases` | bool (por defecto `true`) | Liquidación: lo pagado por bienes que no llegaron vuelve a los POPs del país comprador |

### `rebels/rebel_types.json`

* `min_militant_share` (0,15) y `min_militant_population` (30 000): proporción y número mínimos de partidarios
  militantes para el nivel 3 (riesgo de revuelta). `min_supporter_militancy` no cambia.

### `pops/promotion.json`

* Salida gradual del empleo estatal sobrante: soldados → campesinos (`military_excess`), clero → artesanos
  (`clergy_excess`) y burócratas → oficinistas (`admin_excess`).

### Estado nuevo

* `province.rgo_util`: utilización del RGO. Se guarda; si falta vale 1.
* Movimientos: `level` (0–3), `militant_support`, `militant_share`, `avg_militancy`. `rebel_risk` = nivel 3.
* Derivados, no guardados: `c._reform_fail` (motivos de reformas denegadas por la IA) y
  `market._good_signal` (caché mensual de precio relativo y oferta/demanda).

El guardado sigue siendo **v6**: todo lo nuevo tiene valores por defecto compatibles.

## M6.0 — Mundos

### `worlds/worlds.json`

```json
{"worlds": [{"id": "prototype_earth", "root": "worlds/prototype_earth/"}]}
```

### `worlds/<id>/world.json`

| Clave | Uso |
|---|---|
| `id`, `name`, `description` | Identidad |
| `width`, `height` | Tamaño del mapa (validado contra `map/map.json` y el PNG). `0` en un mundo sin mapa todavía |
| `wrap_x` | Mapa cilíndrico (cámara y dibujo) |
| `map_version` | Versión de la geometría si `map/map.json` no la declara (prototipo terrestre) |
| `default_scenario` | Escenario propio por defecto |
| `enabled`, `status` | `false` lo oculta al jugador (p. ej. Aether en desarrollo) |
| `test_only` | Solo para pruebas automáticas |
| `forbidden_packs` | Paquetes de contenido que el mundo no admite |
| `author`, `version`, `generator` | Informativos |

**Archivos obligatorios del mundo** (sin respaldo compartido):

* `map/provinces.png`, `map/map.json`, `map/geometry.json`, `map/adjacencies.json`;
* `provinces/provinces.json`, `provinces/sea_zones.json`, `states/states.json`;
* `countries/countries.json`, `cultures/cultures.json`, `religions/religions.json`;
* la historia de cada escenario (`history/*.json`).

**Sobrescrituras opcionales:** cualquier archivo compartido con la misma ruta relativa, por ejemplo
`goods/goods.json` o `terrain/terrain.json`.

### `map/map.json` (mundos importados)

Añade `map_version`, que el importador sube cuando cambia la geometría, y `generated` (aviso de no editar).

### `provinces/provinces.json`, `sea_zones.json`, `states.json` (mundos importados)

* Cada entrada lleva además `key`, la clave estable de su semilla.
* Los estados llevan `region`, la clave de la región del autor.
* El motor ignora estos campos; sirven para trazar ids.

### `scenarios/scenarios.json`

* Nuevo: `world` (id del mundo; si falta, `prototype_earth`).
* Nuevo: `enabled` (`false` lo oculta) y `test_only`.
* `history` es ahora una ruta relativa a la carpeta del mundo.

### Fuente de mapas fantásticos

Ver [FantasyMapPipeline.md](FantasyMapPipeline.md):

* `source/map_rules.json`, `land_mask.png`, `terrain.png`, `regions.png` / `regions.json`,
  `province_seeds.json`, `province_overrides.json` y `adjacencies.json`;
* `ids.lock.json` e `ids_remap.json`.

### Guardado v7

* Raíz y cabecera: `world_id`, `map_version` y `scenario`; la cabecera añade `world_name`.
* Una v6 se migra a `prototype_earth`, mapa v1.

### Rutas movidas

`map/`, `provinces/`, `states/`, `countries/`, `cultures/`, `religions/` e `history/` pasan de
`data/victoria_mode/` a `data/victoria_mode/worlds/prototype_earth/`, sin cambios de contenido.
