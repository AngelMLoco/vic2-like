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

## Milestone 4 — Eventos, decisiones y despertar mágico

Contenido **encima** de la simulación existente: los eventos leen el estado real (mercado, POPs, fábricas,
política, guerra, magia) y lo modifican a través de las APIs de cada sistema.

### Módulos

| Módulo | Función |
|---|---|
| `events/VEventSystem` | carga y validación, índice, planificador, MTTH, disparo, cola del jugador, follow-ups, `notify` (on_action) |
| `events/VEventConditions` | compila las condiciones JSON a nodos `[código, args…]` y las evalúa; texto legible del primer fallo |
| `events/VEventEffects` | valida y aplica los efectos usando las APIs de los sistemas; describe efectos para los tooltips |
| `events/VEventAI` | elección de opción de la IA: pesos × modificadores condicionales, tirada determinista |
| `events/VScopedState` | banderas de nación/provincia/estado, variables, modificadores temporales, crónica |
| `events/VDecisionSystem` | decisiones: visibles, disponibles (con motivo), coste, efectos, cooldown, IA |
| `events/VEventDebug` | consola: `fire_event`, `take_decision`, `activate_magic`, `list_available_decisions` |
| `magic/VMagicSystem` | despertar, ramas, yacimientos, extracción, aparición de magos, acceso a tecnologías mágicas |
| `ui/VEventPopup` | ventana de evento con cola, ilustración (`art_key`) y tooltips de efectos |

`VWorldSimulation` solo llama a `VEventSystem.daily` (dentro del día) y `VEventSystem.monthly` (cierre de mes).
`VConditions` no cambia (POPs e inventos).

### Ciclo de vida de un evento

1. **Carga:** `data/victoria_mode/events/*.json` y `magic/events/*.json`.
2. **Validación:** ids duplicados, opciones vacías, condiciones o efectos desconocidos, países, bienes,
   tecnologías y modificadores inexistentes, follow-ups a eventos que no existen. Los errores van a
   `gs.data_errors` y se muestran con `push_error`.
3. **Compilación:** condiciones a nodos con código entero y efectos validados.
4. **Índice:**
   * cadencia × ámbito para los eventos genéricos;
   * nación → sus eventos propios (`tags`): un evento de Frankia no se comprueba para las otras 88;
   * `on_action` → eventos.
5. **Planificador:**
   * Cada día solo se procesa el cubo de naciones del día (`índice % 28`): eventos mensuales siempre,
     trimestrales y anuales escalonados.
   * Los globales se procesan el día 1; los programados (follow-ups) cuando vencen.
   * Los eventos de provincia solo miran conjuntos candidatos: capital, provincias mágicas, ocupadas o
     costeras. Nunca se recorre el mundo ni los POPs.
6. **Filtros baratos:** nación, bandera global requerida, `once`/`cooldown` (historial propio, no el log) y
   presupuesto mensual de 2 eventos «normal» por nación.
7. **Trigger compilado** → **tirada determinista**:
   * MTTH: probabilidad por comprobación = 1 − 0,5^(periodo/MTTH), con modificadores de factor.
   * O `chance`.
   * La clave se mezcla con `rand_from_seed`: el hash de cadenas parecidas sale parecido y sesgaba las tiradas.
8. **Disparo:**
   * Se aplican los efectos inmediatos y se registra en la crónica.
   * **Jugador:** cola de ventanas (`major`/`normal`); `notification` se resuelve sola; `hidden` no se muestra.
   * **IA:** `VEventAI` elige la opción.
   * Después se aplica la opción y se programan los follow-ups.

Ganchos on_action que emiten los sistemas: `war_declared`, `war_ended`, `battle_won/lost`, `province_occupied`,
`government_changed`, `reform_passed`, `election_finished`, `technology_researched`, `invention_discovered`,
`country_enters/leaves_sphere`, `rebellion_started/won`, `factory_closed`, `factory_built`, `magic_activated`,
`decision_taken`.

### Banderas, variables y modificadores

* **Banderas globales:** `gs.flags`, que ya existía.
* **Banderas de nación, provincia y estado, y variables numéricas de nación:** en `gs.event_state`, que se guarda.
* **Modificadores temporales** `{id, source, start, expires, effects}`:
  * Los de nación se suman en `VModifiers.recompute` junto a tecnologías, inventos y reformas. Solo se
    recalculan al añadir, quitar o caducar uno.
  * Los de provincia se agregan en `p["pmods"]` y los leen producción (eficiencia y tamaño del RGO) y población
    (crecimiento, militancia, alfabetización, conciencia).
  * La caducidad es mensual y solo recorre las listas existentes.

### Capa mágica (prototipo)

* **Despertar:** evento global `magic.awakening` definido en datos (trigger configurable: año ≥ 140 y la
  bandera sin activar, MTTH 6 meses).
  * Su efecto `activate_magic` pone `GLOBAL_MAGIC_ACTIVATED` y `magic_unlocked`, que ya usaba
    VTechnologySystem.
  * También siembra yacimientos de forma determinista según el terreno y emite `magic_activated`.
* **Ramas:** el campo existente `country.magic_branches`. Los perfiles de prueba están en
  `magic/prototype_branches.json` (PROTOTYPE).
  * Las tecnologías mágicas declaran `magic_branch` + `min_level` + `requires_flag`;
    `VTechnologySystem.can_research` las filtra con `VMagicSystem.tech_allowed`.
  * Resultado: cada nación desbloquea cosas distintas.
* **Provincias:** `p["magic"] = {potential, deposit}`. Es una capa secundaria y **no sustituye el RGO**.
  Un índice por nación evita recorrer el mapa.
* **Economía:**
  * Los yacimientos producen cristal de maná, que entra al mercado como cualquier bien y paga a los
    trabajadores de la provincia.
  * Cadena: cristal → reactivos arcanos (refinería de maná) → componentes encantados (taller arcano), y
    elixir alquímico (laboratorio).
  * Son fábricas y bienes normales. Mientras el bien está bloqueado no se construyen fábricas que lo usen
    (`VProductionSystem.goods_unlocked`).
* **Magos:**
  * Tipo de POP de datos (`magi` en `pop_types.json`): necesidades, renta, ideología, cultura y religión
    como cualquier otro.
  * Aparecen por promoción rara desde clero, oficinistas y aristócratas alfabetizados, en provincias con
    potencial mágico de naciones con rama (`VMobilitySystem._transfer`: personas reales).
  * También por decisiones (Academia Arcana).
* **Ejército:** modificador `battle_magic`, que el resolver de batalla ya lee, y la unidad prototipo `arcane_support`
  (exige tecnología y se abastece de componentes encantados). Sin cartas todavía.
* **Política:** debate de regulación (prohibir, licencias, fomentar o monopolio del Estado, este último solo
  con rama política), con banderas y modificadores que cambian la aparición de magos, la militancia y el fisco.
* **IA:** investiga tecnologías mágicas disponibles, construye fábricas mágicas rentables (inversión normal),
  elige opciones de eventos mágicos y toma decisiones mágicas.

### Guardado v5

`events` (todo `gs.event_state`) y `p["magic"]` en las provincias. Las definiciones (eventos, decisiones,
modificadores, ramas) vienen de los datos y no se guardan. Las partidas v4 se rechazan.

## Milestone 5 — Equilibrio fantástico, marco de lore y contenido

### Población mágica: capacidad en lugar de ritmo fijo (`magic/VMageModel.gd`)

En M4 los magos crecían a un ritmo fijo por POP fuente, y la curva era exponencial. En M5 crecen hacia la
**capacidad** que cada sociedad puede sostener:

```
objetivo = población × base_share × f_rama × f_alfabetización × f_potencial × f_fe × f_empleo × (1 + mage_capacity)
           + academias × academy_capacity
promoción mensual = (objetivo − magos) × convergence × (1 + mage_promotion + academias × academy_promotion) × oportunidad
```

* **f_rama:** casi nula sin ramas mágicas; crece con la suma de niveles.
* **f_alfabetización:** alfabetización frente a la de referencia.
* **f_potencial:** población que vive en provincias con potencial mágico.
* **f_fe:** actitud mágica de la religión de Estado × tradición mágica de la cultura principal.
* **f_empleo:** con magos en paro, la sociedad sostiene menos.
* **mage_capacity:** suma de regulación, tecnologías y eventos.

La promoción solo ocurre con rama mágica o academia. Se reparte entre POPs fuente alfabetizados de provincias con
potencial, ponderada por potencial, religión y cultura de cada POP. Cerca del objetivo se apaga sola. Las
naciones pequeñas tienen un mínimo mensual, para que también converjan. Por encima del objetivo no hay
promoción, y los magos sin empleo se degradan a oficinistas o emigran.

**Empleo real** (los magos ya no son empleo estatal automático; su oficio es `arcane`):

* **Fábricas mágicas** (`workforce.magi`). Los paga la fábrica; sin magos, la fábrica rinde menos.
* **Plazas del Estado**, cubiertas con la misma tasa en toda la nación:
  * academias (educación);
  * administración mágica (`mage_state_posts`, administración);
  * ejército (`mage_military_posts`, salarios militares).
* **Práctica privada** (sanadores, adivinos). La pagan capitalistas y aristócratas: es una transferencia y
  el dinero se conserva.

Sin plaza, el mago está en paro, lo que reduce sus necesidades, sube su militancia, provoca emigración y crea
presión política. Así puede surgir una **crisis de magos**.

**Fuga de cerebros.** Cada mes, `world_monthly` ordena las naciones que reclutan magos (las que están por
debajo de su objetivo) por atractivo: regulación, academias, empleo de magos, nivel de vida y paz. Los magos
de naciones que los prohíben, persiguen o no emplean emigran hacia ellas con `_transfer` (personas reales) y
disparan el gancho `mage_brain_drain`. `force_emigration` es el efecto `mage_emigration` de los eventos.

**Estado:**

* `c["magic_stats"]` se guarda: contadores acumulados y anuales de formados, degradados, emigrados e
  inmigrados.
* Derivados (se recalculan en un mes): `_magi_info`, que contiene el objetivo, el desglose, el paro y las
  plazas; `_magi_state`, con las plazas y el sueldo del mes siguiente; `_magi_acc`, que es el empleo acumulado
  por las particiones; y `_mil_extra`.

### Política mágica (`magic/VMagicPolicy.gd`)

La regulación de la magia es una **reforma** (`magic_regulation`) con cinco niveles provisionales: Prohibida,
Tolerada, Licenciada, Promovida y Control estatal. Sus efectos son modificadores nacionales: capacidad,
promoción, atracción, investigación arcana, eficiencia de fábricas mágicas, militancia de los magos, tensión
religiosa, plazas estatales y práctica privada.

* No genera movimientos genéricos (`movement: false`).
* En la cámara, cada ideología apoya los cambios que acercan la ley a su postura (`ideologies.json` →
  `issues.magic_policy`, en los datos) y se opone a los que la alejan.
* La IA empuja cada trimestre hacia la postura del partido gobernante, corregida por la situación:
  * clero hostil con muchos magos: más restrictiva;
  * magos en paro: deja de fomentar;
  * guerra con rama militar: control estatal;
  * con academias: no prohíbe.
* Los eventos pueden decretar un nivel (`set_magic_regulation`).

**Religión y cultura.** `religions.json` → `magic_attitude` modula la promoción y la tensión religiosa. La
tensión es militancia adicional del clero, proporcional a la proporción de magos (`_mil_extra`, componente
`magic` del diagnóstico). `cultures.json` → `magic_tradition` modula la promoción.

### Diagnóstico de militancia y conciencia

`VPopulationSystem` separa la militancia en:

* vida, diario, paro, lujo y movimiento;
* cansancio bélico;
* modificadores permanentes;
* modificadores temporales de eventos (nación y provincia);
* magia (regulación y tensión religiosa);
* relajación, base, reformas;
* **eventos** (efectos directos `add_militancy`, medidos en `VEventEffects._change_pops`).

La conciencia se separa en:

* alfabetización;
* modificadores permanentes y temporales;
* pobreza vital y diaria;
* paro;
* base y relajación;
* eventos.

`gs.market["mil_diag"]` / `["con_diag"]` guardan el último muestreo y `["diag_cum"]` los promedios acumulados
desde el inicio (`cumulative_diagnosis`).

### Paquetes de contenido, espacios de nombres y escenarios

* **Escenarios.** `VDataLoader.new_game(scenario_id)` lee `scenarios/scenarios.json`, que define fecha,
  historia y paquetes. El motor ya no asume el año 136. Las partidas guardan el escenario y se recargan con él.
* **Paquetes** (`core/VContentPacks.gd`). Eventos, decisiones, modificadores, plantillas de crónica,
  manifiesto de arte, ramas mágicas y lore se leen de `content/<paquete>/…` en el orden del escenario:
  * `core`: sistémico;
  * `prototype`: Tierra, temporal;
  * `fantasy`: Chronicles of Aether, vacío.

  Un id repetido es un error.
* **Espacios de nombres.** `core.<categoría>.*`, `magic.<área>.*`, `country.<tag>.*`, `region.<id>.*`. La
  categoría de la crónica sale del espacio de nombres o del campo `category`.
* **Historia.** `_apply_province_history` (propiedad, control y núcleos antes de construir los estados),
  `_apply_history` (fecha, capitales, relaciones, alianzas, guerras, gobierno y ejército) y
  `_apply_late_history` (tecnologías, inventos, reformas, banderas, variables, modificadores, ramas mágicas
  y rivales).
* **Biblia de lore** (`core/VLoreLoader.gd`). `content/<paquete>/lore/*.json` se valida contra un esquema
  mínimo y queda en `gs.lore`; no simula. Esquema completo en `docs/LoreBibleSchema.md`.
* **Ramas mágicas.** Una rama admite `n` o `{"level": n, "paths": [...]}`: el nivel no es la escuela.
  `magic/magic_schools.json` es el esquema de escuelas, vacío por ahora; si se rellena, el cargador valida las
  sendas.

### Crónica (`events/VChronicle.gd`)

Cada entrada lleva categoría (politics, war, economy, diplomacy, society, magic), año y un texto narrativo
opcional. Las fuentes son:

* eventos y decisiones, con su título y opción o con el texto `chronicle` del evento, opción o decisión, que
  admite marcadores `{country}`, `{target}`, etc.;
* la **historia emergente**, desde los ganchos on_action que ya existían, con plantillas de
  `content/core/chronicle.json`:
  * guerra declarada (una entrada por guerra);
  * capital ocupada;
  * paz victoriosa, humillante o blanca (el contexto de `war_ended` lleva ahora `result`, `goals`,
    `war_months` y `war_name`);
  * reforma, gobierno, rebelión, esfera, saber arcano, fuga de cerebros y despertar.

La interfaz (Política → Crónica) filtra por categoría y muestra «Año 143 — La magia regresó al mundo.».

### Contenido y arte

* **Eventos.** 109 eventos (56 nuevos). Las cadenas bélicas reaccionan a las bajas reales de cada batalla
  (`battle_losses` / `own_losses`), a la capital ocupada, a la duración de la guerra y al resultado de la paz.
  También hay cadenas económicas, sociales y de sociedad mágica (persecución, integración, academias, gremios,
  paro de magos, fuga de cerebros, religión, ejército y la guerra por el cristal). Las opciones dejan banderas
  que habilitan o bloquean eventos y opciones posteriores.
* **Arte.** `content/core/art_manifest.json` define 24 categorías visuales, con la dirección de arte
  provisional (óleo romántico/naturalista del XIX). Un evento con un `art_key` fuera del manifiesto es un error
  de datos. `tools/art_manifest.py` rellena qué eventos usa cada categoría.
* **Métricas de eventos.** Por tipo, jugador (ventanas mayores y normales, notificaciones, ocultos), IA
  (visibles u ocultos), espacio de nombres y categoría (`event_state.stats`).

## M5.5 — Economía de largo plazo y transición industrial

### Diagnóstico (antes de cambiar reglas)

`economy/VEconomyDiagnostics.gd` hace una instantánea del mundo: trabajo por clase con plazas y paro (RGO,
fábricas, oficinistas, artesanos, Estado, magos), fábricas y niveles, utilización, particiones llenas,
proyectos, capital de capitalistas y aristócratas, salarios por tipo de POP, descomposición del déficit de
necesidades vitales de los pobres, 10 escaseces, rankings por país y migración.

Recorre todo el mundo, así que **solo lo usan pruebas y depuración**. En partida solo hay contadores baratos:

* `note_reason`: motivo de cada mes-nación sin inversión privada (política, capacidad llena, nada rentable,
  poca demanda, faltan insumos, falta mano de obra, falta capital, estados sin plazas, falta tecnología).
* `note_stat`: proyectos iniciados, completados y abandonados por tipo de inversor.

Hallazgos del modelo M5 a 100 años:

1. **El RGO es el gran empleador y su capacidad era fija.** `base_size` sale de los trabajadores iniciales.
   En 75 años los trabajadores rurales pasan de 627 a 930 M y las plazas de 706 a 770 M: paro rural del 25 %.
2. **La industria apenas absorbe población.** Hay unos 8 M de plazas de obrero frente a 930 M de campesinos,
   y la urbanización es del 4 %. Aunque se duplique, no resuelve el paro.
3. **La inversión privada no ocurre el 85–89 % de los meses-nación por política.** Son países no civilizados
   o con políticas sin inversión privada. Además había un único enfriamiento nacional de 3 meses, un solo tipo
   bloqueaba todo el país, y el límite de 6 fábricas por partición estaba oculto en el código.
4. **El déficit de necesidades vitales** (0,66 en el año 75) es un 51 % escasez de materias primas (a ×4 de
   precio) y un 42 % salarios bajos. Con el RGO fijo, la oferta primaria no sigue a la demanda.
5. **Los aristócratas acumulan capital ocioso:** 19,8 M frente a 4,1 M de los capitalistas.
6. **La cadena mágica no tenía consumidores finales relevantes.** Solo la necesidad diaria de los magos: unos
   15 reactivos al mes en todo el mundo, lo que equivale a 1–2 niveles de refinería.

### Desarrollo rural (RGO)

* `p["rgo_dev"]` (se guarda; sin él vale 0) es el nivel de mejoras rurales de la provincia. Cada nivel suma
  +15 % de plazas (**tamaño**) y +2 % de productividad (**eficiencia**). Son dos cosas distintas: las
  tecnologías agrícolas dan eficiencia sin crear plazas, y las mejoras crean plazas.
* **Límite por provincia:** `max_base` + infraestructura × `max_per_infrastructure` + modificador
  `rgo_development_max` (tecnologías agrícolas). Así el campo ayuda pero no absorbe todo el paro: sigue
  habiendo sobrepoblación rural que empuja a migrar e industrializarse.
* **Financiación.** Los aristócratas financian la mejora: es su papel inversor, en el campo y no en fábricas.
  Si no pueden, la hace el Estado con política de construcción estatal. Se exige:
  * paro rural ≥ 8 %;
  * un RGO rentable (renta por trabajador ≥ coste de vida);
  * demanda del bien (escasez, tendencia o precio medio ≥ 85 % del base).
* **Coste.** Bienes de construcción (madera, fertilizante, maquinaria) proporcionales al tamaño del RGO. El
  capital sale de los inversores (`VMoney.destroyed("investment")`) y los bienes se compran al mercado mientras
  dura el proyecto.

### Inversión por capacidad (`economy/VInvestmentSystem.gd`)

* **Capacidad privada.** Son los proyectos simultáneos: 1 + niveles de fábrica / 25 + capitalistas / 40 000 +
  capital / 3000, con un techo de 10, multiplicado por (1 + `investment_capacity`).
  * Una nación pequeña tiene 1 proyecto y una potencia industrial, 3–10.
  * Los inicios por mes son 1 + capacidad / 4.
  * Los inicios por año no pasan de max(3, niveles × 12 %): crecimiento gradual, sin explosión industrial.
* **Capacidad estatal (independiente).** Un proyecto privado no bloquea uno del Estado. Con paro ≥ 8 % el
  Estado lanza un **programa industrial** reservando solo 6 meses de gasto en vez de 12. Respeta insumos,
  demanda y tecnología.
* **Capacidad rural:** 1 + provincias / 20 (máximo 5).
* **Duplicados por estado y tipo.** Puede haber una acería en el estado A y otro proyecto de acería en el B.
  En cada estado entra como mucho una fábrica nueva por mes, porque la mano de obra es local.
* **Puntuación de una fábrica nueva:** margen esperado con precios medios de 6 meses × (1 + escasez + tendencia
  de 6 frente a 12 meses + presión de paro local y nacional + urbanización + bonos de la industria mágica).
  * **Sin margen positivo no se construye.** El paro acelera, pero no justifica fábricas absurdas.
  * La demanda futura cuenta con medias y tendencias, no con una subida de un mes.
* **Mano de obra real:**
  * obreros parados;
  * 10 % del paro rural y 1,2 % de los campesinos alfabetizados (el campo solo llega a la fábrica por
    promoción, que es lenta);
  * menos las vacantes que ya existen y los obreros que reservan los proyectos en construcción del estado;
  * no se construye donde las fábricas aún no encuentran obreros;
  * las fábricas mágicas cuentan además los magos parados.
* **Plazas de fábrica por partición (regla de datos):** `base` + infraestructura × `per_infrastructure` +
  urbanización × `per_urbanisation` + `state_factory_slots` (tecnología), con un máximo de 14.
* **Subvenciones (IA).** Se dan durante 12 meses a fábricas con pérdidas pero cerca de la rentabilidad y con
  plantilla, si el tesoro está sano. Se retiran al vencer o si la fábrica es inviable.
* **Proyectos estancados.** Si los bienes de construcción no llegan, se cuentan; a los 24 meses el proyecto se
  abandona.
* **El jugador** usa las mismas reglas con `government_build`: plazas del estado y un proyecto por estado y
  tipo. El desplegable de construcción explica cada fábrica (margen, demanda, insumos, trabajadores, paro
  local, plazas).

### Economía mágica con consumidores reales

* **Academias:** consumen reactivos arcanos (3 al mes por academia), pagados con el presupuesto de educación.
* **Industria corriente con insumos mágicos:**
  * `arcane_machine_works`: componentes encantados + acero → maquinaria, más barata que la convencional;
  * `alchemical_fertilizer_works`: reactivos + azufre → fertilizante, que piden las mejoras rurales.

  Es demanda aguas abajo real: la magia entra en la industria y en el campo.
* **Inversión mágica.** Tiene bonos por paro de magos, academias, yacimientos y rama económica, pero exige
  viabilidad. Se localiza en estados con yacimientos, magos e infraestructura.

### Correcciones que salieron de las corridas largas (M5.5)

Con la economía ya respondiendo, las corridas de 100 años destaparon tres cuellos más. Ninguno se resolvió
tocando la militancia.

1. **Equilibrio malthusiano demasiado bajo.** El crecimiento solo se detiene con necesidades vitales ≈ 0,45.
   Al mejorar la economía, la población llegaba a 1,6–1,9 mil millones en 100 años y el paro volvía al 25 %.
   Se añade una **transición demográfica**: el crecimiento positivo se multiplica por
   (1 − `demographic_transition` × alfabetización). La mortalidad por pobreza y la realimentación por
   necesidades vitales no cambian, y no hay tope de población.
2. **Dinero impreso por fábricas en pérdidas.** El déficit de caja se «perdonaba» creando dinero. Ahora una
   fábrica sin caja y sin subvención recorta los salarios a lo que cubren sus ventas y su caja
   (`f["wage_cut"]`).
3. **Atesoramiento.** Los depósitos de clases media y alta solo crecían, y el dinero salía de la circulación.
   `bank_dissaving` devuelve cada mes el 1 % de los depósitos al efectivo (consumo de la riqueza).

Además, las mejoras rurales exigen ahora un precio medio ≥ al base (`min_price_ratio` 1,0): con 0,85
producían excedentes de bienes primarios.

**Problema que sigue abierto.** El nivel de precios nominal tiende al suelo (×0,25–0,35) pasados unos 70
años, porque la capacidad productiva crece más deprisa que la demanda (cestas fijas por persona). El
bienestar real se mantiene (necesidades vitales 0,81–0,85), pero las señales de precio pierden resolución.
Ver el informe de pruebas M5.5.
