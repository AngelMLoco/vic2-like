# Pipeline de mapas fantásticos (M6)

Convierte una geografía **diseñada por el autor** en los datos que usa el motor, con el mismo formato que el
mundo terrestre (`VWorldMap`, `VDataLoader`). No inventa el mundo: la forma de la tierra, las regiones, las
capitales y los nombres los decide el autor; la herramienta solo trocea, numera y valida.

El prototipo terrestre sigue usando `tools/map_import/build_world.py` (Natural Earth). Natural Earth no
interviene aquí.

## Carpetas de un mundo

```text
data/victoria_mode/worlds/<id>/
├─ world.json              AUTOR      metadatos (nombre, wrap_x, escenario por defecto, enabled…)
├─ source/                 AUTOR      fuente del mapa (se edita esto)
│  ├─ map_rules.json       obligatorio
│  ├─ land_mask.png        obligatorio
│  ├─ terrain.png          opcional
│  ├─ regions.png          opcional (con regions.json)
│  ├─ regions.json         opcional
│  ├─ province_seeds.json  opcional
│  ├─ province_overrides.json  opcional
│  └─ adjacencies.json     opcional
├─ ids.lock.json           HERRAMIENTA  bloqueo de ids estables: se versiona, no se edita ni se borra
├─ ids_remap.json          HERRAMIENTA  solo tras --allow-id-break: ids viejos → nuevos
├─ map/                    GENERADO   provinces.png, map.json, geometry.json, adjacencies.json
├─ provinces/              GENERADO   provinces.json, sea_zones.json
├─ states/                 GENERADO   states.json
├─ countries/countries.json   AUTOR
├─ cultures/cultures.json     AUTOR
├─ religions/religions.json   AUTOR
└─ history/<escenario>.json   AUTOR
```

**Nunca se editan a mano** `map/*` ni `provinces/*` ni `states/*`: se regeneran. Un cambio permanente del mapa
se hace en `source/` (o en `map_rules.json`) y se vuelve a ejecutar el importador, igual que
`world_rules.json` en el prototipo.

## Uso

```bash
python tools/fantasy_map/build_fantasy_world.py <world_id> --check   # valida la fuente, no escribe
python tools/fantasy_map/build_fantasy_world.py <world_id>           # genera
python tools/fantasy_map/build_fantasy_world.py <world_id> --allow-id-break
```

Requiere `numpy` y `Pillow`. Tiempo orientativo: 1 s para el fixture de 320×180 y 38 s para 2048×1024 con
1.200 provincias.

Después, en Godot, `VWorldValidator.validate_scenario("<escenario>")` comprueba el mundo completo (mapa +
países + culturas + religiones + historia). Lo hace `tests/VictoriaMultiWorldTest`.

## Fuente

### `land_mask.png`

Una imagen con tres colores exactos (sin antialiasing), por defecto:

| Tipo | Color |
|---|---|
| Tierra | `#ffffff` |
| Mar | `#1f4e79` |
| Lago | `#5b9bd5` |

Los colores se cambian en `map_rules.mask_colors`. El importador rechaza la máscara con un mensaje legible si
encuentra:

* colores no declarados (con su posición);
* falta de tierra o de mar;
* dimensiones distintas de `map_rules.width` / `height`;
* masas de tierra o agua menores que `min_island_px` (motas de dibujo).

Cada masa de tierra recibe al menos una provincia y cada lago es una provincia de tipo `lake`.

### `map_rules.json`

| Clave | Uso |
|---|---|
| `seed` | Semilla de las decisiones aleatorias (posición de semillas nuevas, ruido de fronteras) |
| `width`, `height` | Opcionales; si están, la máscara debe medir eso |
| `mask_colors` | Colores de tierra, mar y lago |
| `target_land_provinces`, `target_sea_zones` | Número objetivo de provincias terrestres y zonas marítimas |
| `min_province_px`, `max_province_px` | Tamaños mínimo y máximo (`0` = 4 × la media) |
| `min_island_px` | Por debajo, una masa aislada es un error de dibujo |
| `max_provinces_per_state` | Tamaño máximo de un estado |
| `km2_per_px` | Escala (superficie y población) |
| `border_noise` | Irregularidad de las fronteras (fracción del espaciado medio) |
| `wrap_x` | Mapa cilíndrico (debe coincidir con `world.json`) |
| `terrain_colors` | `{"rrggbb": terreno}` para `terrain.png` |
| `default_terrain_weights` | Terreno sin `terrain.png` |
| `rgo_by_terrain` | Bienes RGO por terreno |
| `population_per_km2`, `life_rating` | Valores por terreno |
| `coastal_fish_chance` | Probabilidad de pesca en provincias costeras |
| `defaults` | Dueño, cultura y religión si no hay región |
| `names` | Plantillas de nombres (`{region} {n}`, `Mar {n}`…) |

### Opcionales

* **`terrain.png`**: terreno por color. Cada provincia toma el terreno mayoritario.
* **`regions.png` + `regions.json`**: regiones del autor. Cada región lleva `key`, `name`, `color`,
  `density` (más o menos provincias), `owner`, `culture` y `religion`. Sin regiones, se crea una región
  provisional por masa de tierra; se sustituye más adelante sin cambiar los ids de provincia.
* **`province_seeds.json`**: `{"seeds": [{"key", "x", "y", "name"}]}`. Fija provincias concretas
  (capitales, ciudades con nombre) con una clave elegida por el autor.
* **`province_overrides.json`**: `{"<clave>": {"name", "owner", "culture", "religion", "terrain", "rgo",
  "population", "life_rating"}}`.
* **`adjacencies.json`**: `{"adjacencies": [{"a": clave, "b": clave, "type": "sea_strait" | "land_crossing",
  "name"}]}`.

## Generación

1. Se clasifican los píxeles y se validan los datos.
2. **Semillas**, en este orden:
   * las del autor;
   * las del bloqueo que siguen en un píxel de su tipo;
   * una por cada masa de tierra, mar o lago que no tenga ninguna;
   * las necesarias para llegar al objetivo, por muestreo del punto más lejano ponderado por la densidad de la
     región.
3. **Partición**: Voronoi con coordenadas deformadas por ruido suave (fronteras orgánicas), calculado por
   *jump flooding*, separado para tierra y mar. Cada provincia conserva el fragmento que contiene su semilla y
   los demás fragmentos pasan a un vecino del mismo tipo.
4. **Tamaños**:
   * las semillas nuevas que quedan por debajo de `min_province_px` se retiran;
   * las provincias por encima de `max_province_px` reciben otra semilla.
5. **Estados**: por región, en grupos contiguos de hasta `max_provinces_per_state`.
6. **Geometría**: centro dentro de la provincia, caja, área, vecinos (con `wrap_x`), distancia a la costa en
   el canal B y `map_version`.

## IDs estables

Los ids de provincia **no** salen del orden de generación, sino de una **clave estable** por semilla.

* Las claves son las del autor (`province_seeds.json`) o automáticas (`L0001`, `S0001`, `K0001`).
* `ids.lock.json` guarda, para cada clave, su id y la posición de su semilla.
* Al regenerar, cada clave conserva su id y su semilla. Las provincias nuevas se añaden al final del rango
  terrestre.
* Si una regeneración **eliminaría o renumeraría** una provincia terrestre (por ejemplo, la tierra donde
  estaba ahora es mar), el importador se **detiene**. Solo continúa con `--allow-id-break`, que:
  * sube `map_version`;
  * escribe `ids_remap.json` (id viejo → id nuevo) para migrar la historia, los eventos y los núcleos.
* El motor exige ids contiguos: tierra, después mar y después lagos. Por eso, añadir provincias terrestres
  **desplaza los ids de los mares y lagos**. La historia y los eventos deben referirse a provincias
  terrestres; si un dato necesita un mar, conviene darle una semilla con clave (`province_seeds.json`) para
  localizarlo en el bloqueo.

## Versión del mapa

`map/map.json → map_version` sube cada vez que cambia la geometría (huella de los ids por píxel, la geometría y
las adyacencias). Regenerar sin cambios no la sube.

* Las partidas guardan `world_id` y `map_version`.
* `VSaveSystem.load_game` **rechaza** un save de otra versión del mapa o de otro mundo, con un mensaje claro.
* El prototipo terrestre declara su versión en `world.json` (`map_version: 1`). Si se regenera con
  `build_world.py` y cambia la geometría, hay que subirla a mano.

## Mundo de prueba

`worlds/test_fantasy/` es un **fixture automático: TEST ONLY — NOT AETHER LORE**. Tiene:

* dos continentes, una isla y un lago;
* 30 provincias terrestres y 7 zonas marítimas;
* tres países `TFA`, `TFB` y `TFC`.

Se regenera con:

```bash
python tools/fantasy_map/make_test_fixture.py
python tools/fantasy_map/build_fantasy_world.py test_fantasy
```

Su escenario `test_fantasy_1` está marcado como `test_only` y no aparece en el selector.

## Poblar Chronicles of Aether

1. Dibujar `worlds/aether/source/land_mask.png` y escribir `map_rules.json`. Opcionalmente, regiones,
   terreno y semillas con nombre.
2. `python tools/fantasy_map/build_fantasy_world.py aether`.
3. Escribir `countries/`, `cultures/`, `religions/` y `history/era1.json`, el lore del autor.
4. `world.json → "enabled": true`, `width`/`height`; en `scenarios.json`, `aether_era1 → "enabled": true`.
5. Validar con `VWorldValidator.validate_scenario("aether_era1")` y pasar `VictoriaMultiWorldTest`.

No hace falta tocar código del motor.
