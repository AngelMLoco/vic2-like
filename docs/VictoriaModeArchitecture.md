# Segunda versión (modo Victoria) — Arquitectura

Chronicles of Aether tiene dos modos que no comparten lógica de juego:

| Modo | Código | Datos | Guardado |
|---|---|---|---|
| A · Prototipo actual (congelado) | `src/legacy/` | `data/legacy/` | `user://chronicles_save.json` |
| B · Segunda versión (Victoria II como esqueleto) | `src/victoria_mode/` | `data/victoria_mode/` | `user://victoria_mode/saves/*.json` |

`src/app/` contiene lo común: el autoload `App` (enrutador de escenas y opciones), el menú
principal (`MainMenu.tscn`) y el tema visual (`UiTheme.gd`).

```
MainMenu ──Nuevo juego──► Elige modo ──► LegacyRoot.tscn   (Modo A, sin cambios funcionales)
         │                          └──► VictoriaGame.tscn (Modo B)
         └──Cargar──► lista de saves del Modo B ──► VictoriaGame.tscn (con save)
```

## Módulos del Modo B

```
src/victoria_mode/
  VictoriaGame.gd        mediador fino: conecta estado, reloj, mapa e interfaz (sin reglas de juego)
  core/
    VGameState.gd        estado completo de la partida (países, estados, provincias, definiciones)
    VDataLoader.gd       construye un VGameState a partir de data/victoria_mode/
    VDate.gd             calendario (año 136, días/meses)
    VTimeController.gd   pausa + velocidades 1–5, emite day_passed / month_passed
    VJson.gd             lectura de JSON
  map/
    VWorldMap.gd         sprite del mapa de IDs + shader + LUTs; picking por píxel
    world_map.gdshader   colores por LUT, fronteras país/estado/provincia/costa, ocupación, selección
    VMapCamera.gd        zoom suave, paneo, WASD, bordes, centrado, límites
    VMapModes.gd         registro de mapmodes (solo deciden colores; misma geometría)
    VMapLabels.gd        etiquetas por nivel de zoom (países / estados+ciudades / provincias)
  population/VPopulationSystem.gd   generación de POPs y agregados
  simulation/
    VWorldSimulation.gd  orden de los sistemas en cada tick diario/mensual
    VRankingSystem.gd    prestigio + industria + militar → ranking, GP/potencias secundarias
  save/VSaveSystem.gd    guardado con save_version y punto de migración
  ui/                    barra superior, panel de provincia, selección de país, ventana nacional,
                         barra de mapmodes, minimapa, banderas e iconos vectoriales, menú de juego
  economy/ politics/ diplomacy/ military/ technology/ events/   (vacíos: fases 5–13)
```

Regla: ningún sistema nuevo se añade a `VictoriaGame.gd`. Cada sistema es un módulo que
recibe el `VGameState` y es invocado por `VWorldSimulation` (lógica) o por la UI (consulta).

## Geometría ≠ datos de juego

* `data/victoria_mode/map/provinces.png` — mapa de IDs (R + G·256 = id; B = distancia a costa).
  Se importa con `importer="keep"` y se lee como `Image` (picking en CPU) y como `ImageTexture`.
* `map/geometry.json` — por id: tipo (land/sea/lake), centroide, bbox, área, vecinos.
* `provinces/provinces.json`, `states/states.json`, `countries/countries.json` — datos de juego.

El shader no conoce propietarios: recibe tres LUTs de 256×N píxeles
(`color_lut` = color del mapmode, `info_lut` = propietario+estado para fronteras,
`overlay_lut` = color del controlador si hay ocupación). Cambiar de dueño o de mapmode
reescribe solo esas LUTs (unos 3.500 píxeles); el PNG nunca cambia.
La arquitectura admite hasta 65.535 ids (R+G); el mapa actual usa 3.457.

## Relación entre entidades

```
World (VGameState)
 ├── Country[tag]            nación: color, bandera, cultura, gobierno, prestigio, tesoro, relaciones,
 │     │                     aliados, guerras, esfera, infamia, presupuesto, magic_branches…
 │     └── provinces[]       DERIVADO: provincias cuyo owner == tag (rebuild_territory)
 ├── State[id]               región geográfica fija (agrupa provincias)
 │     └── StateInstance     (estado, propietario) = "sid:TAG". Si un estado se divide entre
 │           │                países, cada parte es una instancia con sus propias FÁBRICAS.
 │           └── factories[] {type, level, employment, profit}
 ├── Province[id]            unidad mínima. owner (legal) ≠ controller (militar).
 │     ├── RGO               recurso primario (bien de goods.json) trabajado por farmers/labourers
 │     ├── pops[]            POP = tipo + cultura + religión + tamaño + ideología + necesidades…
 │     └── terrain, life_rating, infrastructure, fort, naval_base, cores, occupation
 └── SeaZone[id]             mismo espacio de ids que las provincias (kind = sea / lake)
```

Previstos (ya contemplados en los datos y en el modelo, se implementan en fases siguientes):

* **Good** (`goods.json`): catálogo con categoría y precio base; `rgo` = farm/mine.
  Los bienes `fantasy` llevan `unlock_flag: GLOBAL_MAGIC_ACTIVATED`.
* **Factory** (`factories.json`): inputs/outputs por nivel y plantilla de trabajadores; vive en una StateInstance.
* **Army / Brigade / Navy**: unidades físicas en provincias/zonas marítimas; cada brigada enlaza
  con un Soldier POP de origen. El combate se resolverá vía una interfaz `BattleResolver`
  intercambiable (`BattleResolverVictoriaPrototype` → `BattleResolverCards`).
* **War / CB / Wargoal**: guerras con bandos, warscore −100…+100, CB data-driven (`casus_belli/`).
* **Event / Decision**: motor data-driven (scope, trigger, MTTH, opciones, efectos, flags, cadenas).
* **Technology / Invention**: árbol por categorías + ramas mágicas nacionales tras `GLOBAL_MAGIC_ACTIVATED`.

## Ciclo de tiempo

`VTimeController` (Node) acumula tiempo real según la velocidad y emite `day_passed`.
`VictoriaGame` llama a `VWorldSimulation.on_day()` (presupuesto, investigación) y en
`month_passed` a `on_month()` (crecimiento de POPs, cachés, ranking). La UI se refresca tras cada tick.

## Ranking

`VRankingSystem`: total = prestigio + industria (niveles de fábrica × empleo) + militar
(brigadas, barcos, soldier POPs). Las naciones civilizadas se ordenan antes que las no civilizadas;
las 8 primeras son Grandes Potencias y las 8 siguientes Potencias Secundarias. Se recalcula cada mes.

## Milestone 2 — población, economía, política y tecnología

Nuevos módulos (todos reciben el `VGameState`; ninguno vive en `VictoriaGame.gd`):

```
core/VModifiers.gd            modificadores nacionales = tecnologías + inventos + niveles de reforma
core/VConditions.gd           evaluador de condiciones data-driven (POPs y naciones)
core/VProfiler.gd             medias móviles por sección (ms)
economy/VMarketSystem.gd      mercado interno → esfera → mundial, precios, aranceles, historial
economy/VProductionSystem.gd  RGO, fábricas por partición de estado, artesanos, empleo estatal, inversión
economy/VBudgetSystem.gd      impuestos por estrato, gastos, deuda, banco nacional, IA presupuestaria
population/VPopulationSystem.gd  modelo de POP, cestas de necesidades, consecuencias
population/VMobilitySystem.gd    promoción/democión (reglas en datos), migración interna e internacional
politics/VPoliticsSystem.gd   partidos, elecciones, cámara alta, reformas por niveles, movimientos
technology/VTechnologySystem.gd  investigación, árbol, inventos, base de magia (magic_unlocked)
```

### El ciclo mensual de un POP

```
trabajo (RGO / fábrica / artesanía / empleo estatal)
  → renta (salario, parte del propietario, beneficio, sueldo estatal) − impuesto del estrato × eficiencia
  → compra: vida → diario → lujo, con su efectivo y el llenado del mercado; riqueza sobrante → más lujo
  → ahorro / depósito en el banco nacional (clase media y ricos)
  → crecimiento (vida, life rating, sanidad, tecnología), alfabetización (clero × educación),
    conciencia (alfabetización, prensa, pobreza) antes que militancia (pobreza grave, paro, movimientos)
  → deriva ideológica (estrato, alfabetización, necesidades, sindicatos) → issues
  → promoción / democión / cambio de oficio / migración / emigración
```

### Dinero y mercado

Los productores registran su oferta y los compradores su demanda en el mercado interno de su nación
durante el mes, usando los precios y ratios de llenado del mes anterior. Al cerrar el mes se casa
oferta y demanda: primero dentro de cada nación, después en la esfera (API preparada; hoy sin esferas)
y por último en el mercado mundial, donde los importadores se atienden por orden de ranking.
El precio mundial se mueve según demanda/oferta, acotado a [0,25 ; 4] × precio base, con historial de 24 meses.
El dinero se crea al vender y se destruye al comprar; para que no se acumule fuera de la circulación,
los ricos gastan su excedente en lujo adicional, los capitalistas y aristócratas invierten, y la IA
presupuestaria mantiene el tesoro cerca de 8 meses de gasto (baja impuestos o sube gasto).

### Reparto temporal (rendimiento)

`VWorldSimulation` reparte las provincias en 28 cubos (`id % 28`); el día *d* del mes procesa el cubo *d−1*
(fábricas de las particiones cuya provincia clave cae en el cubo, producción, POPs, movilidad). El cierre de mes
(mercado, presupuesto, tecnología, política, inversión, destinos de migración, agregados, ranking)
ocurre antes del primer día del mes siguiente (`VTimeController` emite `month_passed` antes de `day_passed`).
Nada se ejecuta por frame. Durante los 12 primeros meses del escenario la productividad de cada RGO se
recalibra suavemente hacia la demanda observada (el mapa de prueba reparte recursos al azar).

## M2.11 — Estabilización

* **Agregados por cubos**: los agregados nacionales (población, estratos, alfabetización, votantes,
  capitalistas…) se acumulan durante el recorrido diario por cubos; el cierre de mes ya no recorre
  todos los POPs otra vez (salvo tras cargar o cambios de territorio).
* **Escalonado**: consecuencias lentas de los POPs y movilidad cada 2 meses, deriva ideológica e issues
  cada 3, todas escalonadas por provincia y con pasos proporcionales (mismo ritmo medio).
* **Inversión**: solo invierten los capitalistas; exige demanda real del producto, margen con precios
  medios de 6 meses, insumos disponibles, mano de obra libre, tecnología, historial de beneficios (para
  ampliar) y respeta un tiempo de espera y un máximo de proyectos simultáneos.
* **Auditoría monetaria** (`core/VMoney.gd`): cada fuente o sumidero explícito de dinero (ventas y compras
  al mercado, préstamos, intereses, amortización, construcción, reserva, aranceles, inversión, pérdidas
  perdonadas) se registra; periódicamente se compara la variación de los activos (efectivo y depósitos
  de POPs, caja de fábricas, tesoros) con lo registrado. Residuo medido ≈ 0,001 %.

## Milestone 3 — diplomacia, ejército, guerra, armada y rebeldes

```
src/victoria_mode/
  diplomacy/VDiplomacySystem.gd   relaciones, alianzas, garantías, acceso militar, treguas, puntos diplomáticos
  diplomacy/VInfluenceSystem.gd   influencia de las Grandes Potencias, opinión, esferas
  military/VArmySystem.gd         ejércitos, brigadas <- Soldier POP, reclutamiento, rutas, retirada
  military/VSupplySystem.gd       consumo real de la reserva militar, límite de suministro, desgaste, org/moral
  military/VLeaderSystem.gd       liderazgo de los oficiales, generales y almirantes con rasgos
  military/VBattleResolver.gd     INTERFAZ del combate (resolve_tick)
  military/VBattleResolverVictoria.gd   implementación provisional
  military/VCombatSystem.gd       batallas: inicio, refuerzos, fin, retirada (independiente del resolver)
  military/VMilitaryAI.gd         IA terrestre y naval
  war/VCasusBelliSystem.gd        CB data-driven sobre particiones de estado, justificación
  war/VWarSystem.gd               guerras, aliados, warscore con desglose, asedios, cansancio, IA bélica
  war/VPeaceSystem.gd             coste de objetivos, aceptación de la IA, efectos de paz
  navy/VNavySystem.gd             flotas en zonas marítimas, puertos, transporte, bloqueo, astilleros
  navy/VNavalBattleResolver.gd    combate naval provisional
  rebels/VRebelSystem.gd          facciones rebeldes a partir de los movimientos políticos
  map/VMapUnits.gd                contadores de ejércitos y flotas (dibujo por lotes)
  ui/VUnitPanel.gd, ui/VPeaceWindow.gd
```

### Army -> Brigades -> Soldier POP

Una brigada (3.000 hombres) guarda `source_pop_id` y `source_province_id`. Solo se crea si el POP de
soldados tiene hombres para otra brigada (tamaño >= (brigadas vinculadas + 1) x 3.000). Las bajas de
batalla y de desgaste restan personas al POP (`VArmySystem.apply_casualties`). El refuerzo devuelve a la
brigada como máximo lo que el POP puede sostener (tamaño / brigadas vinculadas). Un stack wipe mata a
todos sus hombres. No hay reserva abstracta de manpower.

### Combate sustituible

`VCombatSystem` crea las batallas cuando un ejército entra en una provincia con enemigos, incorpora a
los que llegan, termina la batalla, ordena retiradas (o stack wipe) y comunica el resultado a
`VWarSystem`. Cada día delega en `VCombatSystem.resolver().resolve_tick(battle, gs)`, que solo aplica daño
mediante `VCombatSystem.damage_brigade()`. El futuro `VBattleResolverCards` se instala con
`VCombatSystem.set_resolver(...)` sin tocar ejército, movimiento, ocupación ni warscore.

### War -> Wargoals

Una guerra tiene bandos reales (los aliados deciden si se unen), objetivos (CB sobre particiones de
estado o sobre el país) y un warscore con cuatro componentes: batallas (+-40), ocupación (valor de las
provincias ocupadas; la capital vale el triple), bloqueo y *ticking* (objetivos controlados; el defensor
gana warscore si resiste más de un año). La ocupación cambia `controller`, nunca `owner`; la propiedad
solo cambia en `VPeaceSystem.apply` -> `gs.change_owner` -> la simulación y el mapa se actualizan por la
señal `ownership_changed`. Tras la paz: treguas, control restaurado y ejércitos de vuelta a casa.

### Fleet -> Ships -> transported armies

Las flotas están en una zona marítima o atracadas en una provincia costera (puerto). Navegan zona a zona
y solo atracan en puertos propios, aliados o con acceso. Un ejército embarca en una provincia costera
con la flota atracada allí o en una zona vecina; la capacidad de transporte (suma de `transport`) limita
las brigadas; el ejército viaja en `fleet.transported_armies` y desembarca en una costa vecina accesible.

### Influence -> Sphere -> Market

Las Grandes Potencias del ranking existente generan influencia mensual repartida por prioridades; con
opinión «amistoso» pueden meter a un país en su esfera (`sphere_leader`). `VMarketSystem.clear_month` ya
agrupa a los países de cada esfera y casa su comercio antes del mercado mundial (comprobado: un miembro
importa antes que un país mejor clasificado). Si una GP pierde el rango, tras un periodo de gracia pierde
su esfera y deja de generar influencia.

### Movement -> RebelFaction

Los movimientos de `VPoliticsSystem` (apoyo, organización, radicalismo) son la única fuente de rebeldes:
con `rebel_risk`, organización y radicalismo altos y POPs muy militantes se forma una facción; al
organizarse se alza con brigadas formadas por personas reales de esos POPs. Ocupan provincias
(controlador `REB`), combaten al ejército nacional y, si mantienen la capital o el 30 % de las provincias
3 meses, imponen su demanda (subir la reforma o cambiar el partido gobernante). Si se disuelven, los
supervivientes vuelven a sus POPs.

### Guerra y economía

La ocupación reduce la producción del RGO (x0,4), impide al propietario cobrar impuestos allí y reduce
la producción de las fábricas del estado; la migración evita las provincias ocupadas. El bloqueo recorta
el acceso del país al mercado mundial (exportaciones e importaciones, y con ello los aranceles). El
suministro de los ejércitos consume la reserva militar, que se compra al mercado según el slider. Las
bajas reducen la población; el cansancio bélico eleva la militancia y reduce la producción industrial.

### Ticks

Diario (`VWorldSimulation.military_day`): movimiento, combate, suministro/desgaste/organización
(escalonado cada 3 días por ejército), refuerzo, asedios y warscore, armada y bloqueos, IA militar (cada
5 días por nación). Mensual: diplomacia, influencia, CB/justificaciones, cansancio, IA bélica y de paz,
líderes, rebeldes.

## M3.1 — Arquitectura de rendimiento

Objetivo: menos recorridos globales, menos búsquedas redundantes y menos asignaciones, sin cambiar las
reglas del juego. Todo lo de esta sección es **derivado**: no se guarda (save_version sigue en 3) y se
reconstruye al cargar o al primer uso. Las claves privadas `_…` de ejércitos, brigadas, flotas y guerras se
eliminan al guardar (`VSaveSystem._public`); las de países y provincias ya quedan fuera por lista blanca.

### Índices de unidades (`military/VUnitIndex.gd`, `gs.unit_index`)

| Índice | Contenido | Se actualiza en |
|---|---|---|
| `armies_by_province` | provincia → ejércitos desembarcados | crear, destruir, mover, embarcar, desembarcar |
| `armies_by_country` | nación → ejércitos regulares | crear, destruir, alzarse en rebeldía |
| `fleets_by_country` / `fleets_by_location` | flotas | crear, hundir, mover |
| `sieging` | ejércitos en provincias de otro controlador (o rebeldes) | al llegar a una provincia |
| `damaged` | ejércitos con brigadas por debajo de su fuerza | `apply_casualties`, `attach_brigade` |

`armies_in`, `country_armies`, `country_fleets`, `fleets_at` y `brigades_in` usan los índices; ningún sistema
recorre `gs.armies` para buscar por provincia o nación. `VUnitIndex.verify()` compara el índice con una
reconstrucción completa (lo usa `VictoriaM3Test`). Los teletransportes (fin de guerra, pruebas) pasan por
`VUnitIndex.move_army` / `move_fleet`.

### Versiones e invalidación

* `gs.access_version`: sube al declarar o unirse a una guerra, retirarse un participante, firmar la paz,
  formar o romper alianzas, dar o retirar acceso militar y cambiar la propiedad de provincias. Invalida la
  caché de relaciones bélicas (`VWarSystem._relations`: enemigos y aliados en guerra por nación, O(1)), la
  caché de rutas, las regiones de acceso y los destinos estratégicos de la IA.
* `gs.path_epoch`: sube si un ejército encuentra bloqueado un paso de una ruta cacheada.
* `gs.controller_version`: sube en cada cambio de controlador (`VWarSystem.set_controller`, único punto).
* `gs.ws_values_month`: mes de los valores de warscore por provincia (−1 = recalcular).

### Rutas (`VArmySystem.find_path`)

1. Componentes conexas terrestres (estáticas): destino en otra masa de tierra → sin ruta, sin A*.
2. Caché de rutas por (nación, facción, origen, destino) válida para una versión de acceso y época. No incluye
   la velocidad: el coste es proporcional a 1/velocidad, así que la ruta óptima es la misma.
3. Regiones de acceso: componente conexa de las provincias en las que la nación puede entrar, calculada por
   inundación una vez por región. Origen y destino en regiones distintas → sin ruta, sin A*. Por eso A*
   (montículo binario) solo se lanza cuando va a tener éxito.
4. Presupuesto de la IA: como máximo `VMilitaryAI.PATH_BUDGET` búsquedas nuevas por día. Las demás órdenes
   esperan en cola uno o varios días; las rutas en caché no cuentan.

### IA militar

Solo trabaja con las naciones a las que les toca ese día (≈1/5). Los destinos estratégicos (objetivos de
guerra, provincias propias ocupadas, capital o frontera enemiga) se recalculan cada `STRATEGIC_DAYS` (10) días
o cuando cambia el acceso. La elección táctica (cada 5 días) ordena los candidatos por distancia² y evalúa el
peligro (índice por provincia: provincia y vecinas) solo hasta encontrar el primer destino aceptable, con el
mismo resultado que evaluarlos todos. Una decisión dispara como mucho una búsqueda A*.

### Guerra y armada orientadas a eventos

* Ocupación: valor de warscore por provincia (`_wsv`), y por nación el valor total y el valor ocupado por
  cada controlador. Se mantiene en `set_controller` y se recalcula una vez al mes (la población cambia).
  `occupation_ws` cuesta O(participantes²).
* Bloqueo: recuentos de costas bloqueadas por bloqueador solo para las naciones afectadas ese día o el
  anterior; `blockade_ws` se deriva de ellos.
* Warscore por objetivos: se vuelve a contar el control de la partición solo si cambió algún controlador.
* Asedios: solo se recorre el índice `sieging`.

### Suministro y refuerzo

* Consumo por ejército cacheado a plena fuerza (`_need`; se invalida al cambiar sus brigadas) y multiplicado
  por la fracción de fuerza.
* Límite de suministro cacheado por (provincia, versión de acceso, mes).
* POP de origen de cada brigada cacheado (`_pop`): los POPs nunca se eliminan de su provincia.
* Ejércitos asentados: con todas las brigadas en su organización máxima y la moral y el suministro estables,
  el bucle de organización no cambiaría nada y se omite (resultado exacto).
* El refuerzo solo recorre el índice `damaged`.

### POPs y economía (mismo cálculo, menos operaciones)

* Compra de necesidades con costes y llenados planos por (nación, tipo); sin arrays temporales por POP.
* Issues: el resultado depende solo de (ideología dominante, tipo, máscara de reglas condicionales). Se
  comparte entre POPs como diccionario de solo lectura, sin `duplicate()` por POP.
* Deriva ideológica sin comparaciones de cadenas; condiciones de promoción precompiladas a códigos enteros.
* Agregados nacionales sumados en variables locales por provincia.
* Producción por provincia en una sola pasada por POP (RGO → artesano → empleo estatal → prestaciones, el
  mismo orden por POP que las tres pasadas anteriores) con impuestos en línea.
* Movimientos políticos con reformas precompiladas; demanda de POPs al cierre del mes con cestas resueltas
  una vez; destinos de migración con selección parcial de los 6 mejores.

### Medición

`VProfiler` registra llamadas, total, media real y máximo por sección, además de contadores (rutas, nodos,
aciertos de caché, IA). `tests/VictoriaPerformanceBenchmark` mide 1, 5 y 10 años de la misma partida y
compara la huella de la simulación con una línea base (ver Testing).

## M3.2 — Almacén de POPs (estructura de arrays) y estabilidad política

### `population/VPopStore.gd` (`gs.pops`)

Un POP es un **slot entero**. Cada campo caliente es un array global: tamaño, efectivo, banco, renta, empleo,
alfabetización, conciencia, militancia, necesidades, paro, empuje de movimiento e ideología (matriz plana
`slot × n_ideo`). Los campos fríos van en arrays aparte: issues como diccionario compartido de solo lectura,
producto artesano, destinos de migración/promoción y enlaces de brigada. Las provincias guardan sus slots en
`p["pop_slots"]`.

* **Por qué `Array[int]`/`Array[float]` y no `Packed*Array`** (medido, 20.000 lecturas+escrituras):
  `Dictionary` por POP 4,7 ms · `obj.packed[i]` 3,4 ms · `Array` tipado con alias local 0,9 ms. Un Packed es un
  valor con copia-en-escritura: un alias local (`var cash := store.cash`) se separa del almacén en la primera
  escritura, y escribir a través del miembro cuesta casi lo mismo que el diccionario. Los `Array` tipados son
  referencias, así que los bucles calientes toman alias locales y escriben en el almacén directamente.
* **Ids numéricos:** tipo, cultura, religión, ideología y empleador son enteros. Cada tabla tiene su nombre ↔ id,
  y los tipos con reglas propias se resuelven una vez (`T_FARMERS`, `T_SOLDIERS`…). Los bucles calientes no
  comparan cadenas.
* **Datos por tipo:** estrato, fracción de gasto, factor de alfabetización, trabajador manual, empleo, sueldo
  estatal, peso de voto y migrante, en arrays indexados por `type_id`.
* **Alta y baja:** `allocate()` usa la lista libre (nunca se compacta) y `free_slot()`. `merge(src, dst)` hace
  medias ponderadas, suma tamaño y dinero, traslada los enlaces de brigada y deja el id de `src` como alias
  de `dst`.
* **Ids estables:** `id_to_slot` en O(1), incluidos los alias. Las brigadas (`source_pop_id`) y las facciones
  rebeldes (`supporting_pops`) siguen funcionando aunque el POP se fusione.
* **Compatibilidad:** `get_pop_details(slot)` construye un diccionario temporal para la UI (un POP a la vez).
  `get_pop_summary`, `get_pop_field`, `get_pop_type_name`, y `VPopulationSystem.sizes_by`, `ideology_mix`,
  `weighted_average` y `needs_average` siguen sirviendo a la UI con nombres.
* **Guardado v4:** columnar (`to_save`/`from_save`). Las issues van como tabla de diccionarios distintos más un
  índice, y la carga reconstruye las listas de las provincias, los alias y los enlaces de brigada.
* **`verify()`:** comprueba listas de provincias, slots libres, ids y población (lo usa `VPopStoreTest`).

### Sistemas sobre el almacén

* **`VPopulationSystem.process_province`:** alias locales de los arrays, necesidades en una matriz por
  (país × `type_id` × 6), demanda por niveles en una matriz (país × tipo × 3) y agregados nacionales con arrays
  por tipo y estrato. Ningún diccionario por POP.
* **`VProductionSystem.process_province`:** una pasada por POP con códigos enteros. El sueldo estatal y el gasto
  imputado se precalculan por tipo y los impuestos se calculan en línea.
* **`VMobilitySystem`:** reglas de promoción por `type_id` y condiciones precompiladas sobre el almacén.
  `_transfer` mueve personas al POP coincidente (mismo tipo, cultura y religión) o crea uno nuevo.
* **Política, rebeldes, guerra (jingoísmo), auditoría monetaria y UI:** leen el almacén.
* **Fusión anual** (`merge_similar`): solo une POPs de la misma provincia, tipo, cultura y religión con issues,
  ideología, alfabetización, militancia y conciencia parecidas. Como `_transfer` ya reutiliza el POP
  coincidente, en la práctica no aparecen duplicados (0 fusiones en 50 años). El número de POPs crece despacio
  por combinaciones nuevas (≈20.000 → ≈23.000 en 30 años), sin fragmentación.

### Militancia: diagnóstico y equilibrio

`VPopulationSystem` acumula en cada paso lento las contribuciones mensuales a la militancia, ponderadas por
tamaño: vida, diario, paro, lujo, decaimiento base, relajación, movimientos, cansancio bélico, modificadores y
reformas. `gs.market["mil_diag"]` guarda la media del último mes y `VictoriaBalanceTest` la imprime cada año.

Diagnóstico antes de corregir (30 años):
* Todas las fuentes son independientes del nivel de militancia. El único freno era una base constante de
  −0,015/mes, y el paro y el diario escalan con la conciencia, que crece con la alfabetización.
* La mayoría de los POPs estaban topados en 0 (neto negativo), mientras que un subconjunto con neto positivo
  (pobreza, la reforma «reuniones prohibidas», guerra, movimientos) crecía linealmente sin límite.
* El neto medio salía negativo y aun así la media mundial subía.
* Además, el radicalismo de un movimiento con apoyo entre el 3 % y el 8 % quedaba congelado y seguía
  empujando la militancia aunque el movimiento ya no creciera.

Correcciones (sin bonificaciones globales):
* **Relajación proporcional** (`militancy_relaxation`): −k × militancia al mes. Hay un equilibrio estable
  mil* = fuentes netas / k, en lugar de una deriva lineal hacia 10.
* **Reforma de subsidio de paro:** reduce la parte de la militancia causada por el paro
  (`unemployment_relief_factor` × nivel de la reforma × presupuesto social, con un máximo del 80 %).
* **Movimientos que no crecen:** su radicalismo se enfría 0,01 por trimestre.
* **Cansancio bélico:** ya decaía 1 punto al mes en paz (de 30 a 0 en 2,5 años); no se ha cambiado.
