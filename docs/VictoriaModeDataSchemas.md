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
