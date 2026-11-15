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
