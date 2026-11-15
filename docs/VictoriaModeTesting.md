# Segunda versión — Pruebas

Ejecutable usado: Godot 4.4.1 (consola). Sustituir `GODOT` por la ruta local.

## Automáticas

```bash
# 1. Importar recursos y compilar todos los scripts (muestra errores de parseo)
"$GODOT" --headless --path . --import

# 2. Prueba de humo del Modo B (sale con código 0 si todo pasa)
"$GODOT" --headless --path . res://tests/VictoriaSmokeTest.tscn

# 3. Arranque del prototipo antiguo y del menú (no debe aparecer ningún ERROR)
"$GODOT" --headless --path . res://src/legacy/LegacyRoot.tscn --quit-after 90
"$GODOT" --headless --path . --quit-after 60

# 4. Capturas de pantalla (necesita ventana; abre el juego unos segundos)
"$GODOT" --path . res://tests/VictoriaScreenshots.tscn -- <carpeta_salida>

# Regenerar el mapa (Python 3 + numpy + Pillow)
python tools/map_import/build_world.py            # descarga Natural Earth si falta
python tools/map_import/build_world.py --offline  # solo caché
```

`VictoriaSmokeTest` comprueba: >2000 provincias, >500 estados, >60 naciones vivas, año 136,
naciones con varios estados, estados divididos, 8 Grandes Potencias, picking por píxel,
selección de país desde el mapa, inicio de partida, todos los mapmodes, panel de provincia,
todas las pestañas nacionales, avance de 62 días, cambio del tesoro y de la población,
ocupación sin cambio de propietario, `change_owner`, guardado y carga (fecha, nación, POPs).

## Último resultado (milestone 1)

* Import: sin errores de script.
* Smoke test: 22/22 OK. Carga del mundo ≈ 300 ms; escena completa ≈ 1,1 s.
* Prototipo antiguo (LegacyRoot) y menú principal: sin errores.
* Capturas revisadas: menú, selector de modo, selección de nación (mundo y Frankia),
  zoom de estados, zoom de provincias, mapmodes cultura/recursos/diplomático, ventanas
  de población/presupuesto/producción, rayado de ocupación.

## Prueba manual recomendada (milestone 1)

1. Abrir el proyecto y ejecutar (F5). Debe aparecer el menú principal (no el mapa).
2. Nuevo juego → Prototipo actual: el prototipo antiguo funciona; «« Menú principal» abajo a la izquierda (o Ctrl+M) vuelve.
3. Nuevo juego → Segunda versión: mapamundi + ranking + ficha de nación.
   Clic en un país del mapa o de la lista; «Centrar en el mapa»; JUGAR.
4. En partida: rueda = zoom hacia el cursor; arrastrar (izq./centro/der.) = paneo; WASD/flechas;
   cursor en los bordes; clic en el minimapa. Las etiquetas pasan de países → estados → provincias.
5. Clic en provincia → panel (propietario/controlador, RGO, POPs…). Clic en una zona marítima.
6. Mapmodes: botones abajo a la derecha o teclas 1–9, 0.
7. Pestañas F1–F8 o iconos de la barra superior. En Presupuesto, mover sliders y ver el balance.
8. Espacio = pausa; +/- = velocidad; Inicio = centrar en la capital.
9. Esc → Menú del juego → Guardar; luego Cargar (también desde el menú principal → Cargar partida).

## Pendiente de verificación manual

* Rendimiento en GPUs integradas (el shader hace 8 lecturas de textura por píxel).
* Desplazamiento por bordes en monitores múltiples / ventana sin foco.
* Escala de interfaz distinta de 1.0 (Opciones).

## Milestone 2

```bash
# Prueba de humo ampliada (incluye un año simulado con la interfaz cargada)
"$GODOT" --headless --path . res://tests/VictoriaSmokeTest.tscn
# Balance y rendimiento sin interfaz: N años sin intervención (VBAL_DEBUG=1 añade volcado de mercado y de Frankia)
"$GODOT" --headless --path . res://tests/VictoriaBalanceTest.tscn -- 10
```

La prueba de humo añade: POPs con necesidades/efectivo/issues, renta de los POPs, oferta y demanda,
cambio de precios, producción RGO, fábricas que consumen insumos y producen, satisfacción en [0,1],
desempleo real (RGO sin plazas), impuestos que reducen la renta neta, presupuesto que mueve el tesoro,
aranceles que encarecen importaciones, elecciones con POPs reales, la cámara liberal rechaza reformas sociales
y aprueba una política, tiempo de espera entre reformas, las reformas no saltan niveles, investigación,
tecnología completada, invento activado, un año completo sin error, cambio de alfabetización, promoción y
migración, guardado/carga de tesoro, deuda, precios, tecnologías, reformas, fábricas y efectivo de los POPs,
y rechazo limpio de partidas v1. **Último resultado: 0 fallos.**

`VictoriaBalanceTest` (10 años, sin jugador, determinista) — último resultado:

| Año | Pobl. (M) | Vida | Diario | Lujo | Paro | Milit. | Conc. | Alfab. | Fábricas abiertas/cerradas | Precio mediano |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 711 | 1.00 | 0.50 | 0.10 | 0.00 | 1.00 | 0.59 | 0.06 | 119/0 | 1.00 |
| 1 | 715 | 0.72 | 0.27 | 0.07 | 0.03 | 0.93 | 0.50 | 0.08 | 92/29 | 0.96 |
| 5 | 728 | 0.73 | 0.30 | 0.06 | 0.03 | 0.84 | 0.43 | 0.12 | 344/33 | 1.01 |
| 10 | 736 | 0.66 | 0.28 | 0.08 | 0.05 | 0.82 | 0.59 | 0.17 | 920/129 | 0.92 |

Sin estados degenerados (colapso demográfico, todos ricos, precios disparados, cierre total de fábricas,
paro masivo, militancia mundial extrema, todas las fábricas con beneficio). En 10 años: 15 naciones celebran
elecciones, 116 cambios de reforma, 183 tecnologías y 22 inventos.

Rendimiento (Godot 4.4.1, equipo de desarrollo con GPU AMD RX 6800, headless):

| Sección | Media | Máx. |
|---|---|---|
| Carga del mundo | 630 ms | — |
| Tick diario (un cubo de 1/28 de las provincias) | 24 ms | 54 ms |
| Producción / población / movilidad por cubo | 7 / 17 / 8 ms | — |
| Cierre de mes total | 265 ms | 356 ms |
| · mercado | 22 ms | 42 ms |
| · sistemas nacionales (presupuesto, tecnología, política, inversión) | 116 ms | 157 ms |
| · agregados de POPs | 64 ms | 95 ms |
| Un año simulado sin interfaz / con interfaz | ≈13,5 s / ≈12,4 s | — |

Pendiente: el cierre de mes (~0,27 s) se nota como un pequeño tirón a velocidad 5; repartir también los
sistemas nacionales entre días es la siguiente optimización.

## M2.11 y Milestone 3

```bash
# Suite de M3: diplomacia, influencia/esferas (incluido el mercado de esfera), ejército, armada, rebeldes
# e integración determinista Frankia contra Liga Renana (IA desactivada con gs.flags["ai_disabled"])
"$GODOT" --headless --path . res://tests/VictoriaM3Test.tscn
# Balance de 20 años con guerras, esferas, rebeldes y auditoría monetaria
"$GODOT" --headless --path . res://tests/VictoriaBalanceTest.tscn -- 20
# Sonda de rendimiento por secciones
"$GODOT" --headless --path . -s tests/VictoriaPerfProbe.gd
```

`VictoriaM3Test` comprueba, entre otras cosas: relaciones limitadas a −200…200, costes y tiempos de espera
de las acciones, aceptación de alianzas por la IA, treguas que bloquean declaraciones, influencia solo para GP,
entrada en esfera y comercio por el nivel de esfera de `VMarketSystem` (`sphere_key`/`market_chain`),
brigadas de 3.000 vinculadas a `source_pop_id`/`source_province_id`, bajas que reducen el Soldier POP,
refuerzo limitado por el POP, movimiento por adyacencias con acceso militar, suministro desde el stockpile,
desgaste, combate con `VBattleResolver` sustituible, retirada y aniquilación, ocupación que cambia solo el
controlador, warscore con componentes y limitado a ±100, wargoals y CB por particiones de estado, paz
(propiedad cambia solo en la paz), flotas en zonas marítimas, transporte, bloqueo que reduce el comercio
mundial, combate naval, facciones rebeldes con brigadas de POPs reales y guardado v3 (rechazo limpio de v2).
**Último resultado: 0 fallos.** La prueba de humo sigue en **0 fallos**.

`VictoriaBalanceTest` (20 años, sin jugador, IA activa, determinista) — último resultado: **0 problemas**,
auditoría monetaria con residuo ≈ 0 en todos los meses.

| Año | Pobl. (M) | Vida | Diario | Lujo | Paro | Milit. | Fábricas abiertas/cerradas | Guerras (total) | Brigadas media/máx | Esferas (miembros) | Rebeldes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 711 | 1.00 | 0.50 | 0.10 | 0.00 | 1.00 | 119/0 | 0 | — | 0 | 0 |
| 1 | 715 | 0.76 | 0.39 | 0.08 | 0.00 | 0.93 | 98/31 | 1 | 10.8 / 39 | 0 | 0 |
| 5 | 723 | 0.79 | 0.37 | 0.05 | 0.01 | 0.82 | 159/33 | 26 | 17.9 / 85 | 1 | 0 |
| 10 | 738 | 0.81 | 0.37 | 0.04 | 0.03 | 0.76 | 246/37 | 34 | 21.6 / 132 | 19 | 0 |
| 15 | 765 | 0.87 | 0.40 | 0.06 | 0.04 | 0.63 | 303/45 | 43 | 20.4 / 89 | 16 | 0 |
| 20 | 789 | 0.83 | 0.40 | 0.08 | 0.05 | 0.71 | 345/37 | 54 | 21.4 / 90 | 14 | 14 |

Necesidades de vida a 20 años: estables en ≈0,80–0,88 (sin deriva deflacionaria tras M2.11; la ejecución de 30 años queda pendiente).
Industrialización controlada: 119 → ≈250 fábricas en 10 años (antes de M2.11 eran ≈920).

Rendimiento (mismo equipo, headless, 20 años):

| Sección | Media | Máx. |
|---|---|---|
| Tick diario total | 31 ms | 351 ms |
| · día militar (IA, movimiento/combate, armada, suministro, guerra) | 11,6 ms | 318 ms |
| ·· suministro | 7,5 ms | 20 ms |
| ·· IA militar | 1,4 ms | 305 ms (picos raros de búsqueda de rutas) |
| Cierre de mes | 211 ms | 258 ms |
| · auditoría monetaria | 14 ms | 17 ms |
| Un año simulado sin interfaz | 15–23 s (≈17 s típico) | — |

**Objetivo no cumplido:** el año headless sigue por encima de 8 s (≈9,6 s tras M2.11 sin guerra; ≈17 s con
M3). El cierre de mes sí está cerca del objetivo (≈210 ms frente a 150 ms). Siguientes optimizaciones:
repartir los sistemas nacionales y el suministro entre días, y cachear rutas de la IA entre ticks.

## M3.1 — Pasada de rendimiento

```bash
# Benchmark fijo: misma partida, puntos de control en 1, 5 y 10 años (IA activa, sin jugador)
"$GODOT" --headless --path . res://tests/VictoriaPerformanceBenchmark.tscn -- 10
# Fijar la huella actual como línea base de determinismo (user://bench_baseline_10.json)
VBENCH_SET_BASELINE=1 "$GODOT" --headless --path . res://tests/VictoriaPerformanceBenchmark.tscn -- 10
```

El benchmark imprime ms/año por sistema, llamadas/total/media/máximo de cada sección de `VProfiler`, los
contadores de rutas e IA y una huella de la simulación (población, fábricas, guerras, esferas, brigadas, bajas,
rebeliones, vida, precios) comparada con la línea base. **No falla por tiempo absoluto**: avisa si la IA militar
supera el 15 % de la simulación, la capa militar el 40 %, el cierre de mes el 40 %, si los aciertos de caché de
rutas bajan del 30 %, si A* expande de media más de 400 nodos o si el pico diario supera 12× la media.

### Antes / después (mismo equipo, 10 años, misma partida)

| Medida | Antes (HEAD 3c59b70) | Después | Cambio |
|---|---|---|---|
| Año headless (media 10 años) | 18,6 s | **10,5 s** | −43 % |
| Año 1 / año más lento | 12,0 s / 23,1 s | 8,9 s / 11,8 s | |
| Tick diario: media / máx. | 44,6 / 367 ms | 24,5 / 87 ms | |
| Cierre de mes: media / máx. | 186 / 287 ms | 125 / 176 ms | |
| Capa militar diaria: media / máx. | 23,2 / 336 ms | 8,1 / 68 ms | −65 % |
| IA militar (terrestre + naval) por año | 3,89 s | 0,85 s | −78 % |
| A* por año | 1,24 s (5.021 búsquedas, 135 nodos de media) | 0,21 s (4.056, 31 nodos) | −83 % |
| Suministro por año | 2,12 s | 1,11 s | |
| Población (cubos) por año | 4,11 s | 2,77 s | |
| Producción (cubos) por año | 2,48 s | 2,13 s | |
| Movilidad (cubos) por año | 1,22 s | 1,08 s | |

Rutas en 10 años: 12.812 peticiones, 6.756 aciertos de caché (53 %), regiones de acceso que resuelven los
destinos inaccesibles sin A*, 66 órdenes esperando en cola por el presupuesto diario.

Huella tras 10 años frente a la línea base: población 737,9 → 738,9 M, vida 0,809 → 0,791, guerras 34 → 34,
esferas 19 → 20, brigadas 1.911 → 1.798. Las fábricas (212–251) y el máximo de brigadas de una nación (77–132)
varían entre ejecuciones con cambios mínimos de orden de la IA: la guerra es caótica. La simulación es
determinista: dos ejecuciones del mismo código dan resultados idénticos.

### 20 y 30 años (`VictoriaBalanceTest`)

**0 problemas** en ambos. Los 20 primeros años de la ejecución de 30 coinciden exactamente con la de 20.

| Año | Pobl. (M) | Vida | Diario | Milit. | Conc. | Fábricas | Guerras (total) | Brigadas media/máx | Esferas | Rebeldes |
|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 739 | 0.79 | 0.37 | 0.76 | 0.44 | 212 | 34 | 20,3 / 93 | 20 | 0 |
| 20 | 781 | 0.81 | 0.35 | 0.92 | 0.51 | 343 | 62 | 29,5 / 151 | 21 | 9 |
| 30 | 828 | 0.76 | 0.26 | 1.11 | 0.84 | 471 | 82 | 28,7 / 165 | 21 | 21 |

Necesidades de vida estables (0,76–0,85). Industrialización gradual (119 → 471 en 30 años). A los 30 años
suben militancia y conciencia y aparecen más rebeliones (riesgo en 14 naciones): es la tendencia política
esperada sin eventos ni reformas guiadas; queda para el balance de M4.

### Objetivo < 8 s/año: no alcanzado

Los tres mayores costes restantes (tramo de años 5–10):

1. Población (necesidades, consecuencias, ideología, issues, agregados): ≈ 2,8 s/año, 30 % de la simulación.
2. Producción por provincia (RGO, artesanos, empleo estatal, prestaciones): ≈ 1,8 s/año, 17 %.
3. Suministro militar: ≈ 1,2 s/año, 11 % (seguido de la movilidad, ≈ 1,1 s/año).

Se probaron optimizaciones adicionales sobre el mayor (población): costes planos, issues compartidos por
máscara, deriva sin comparar cadenas y agregados en locales. Bajó de 4,1 a 2,8 s/año. Lo que queda es
**estructural**: cada POP es un `Dictionary` de GDScript y el mes completo hace unas 50–80 lecturas y escrituras
de diccionario por POP (≈ 20.000 POPs), a ≈ 0,15–0,3 µs cada una. Bajar de 8 s requeriría:

* Pasar los POPs a estructura de arrays (`PackedFloat64Array`/`PackedInt32Array` por campo, con índices por
  provincia). Es una reescritura de población, producción, movilidad, política y guardado. Ganancia esperada:
  entre 2× y 3× en esos sistemas, que llevaría el año a ≈ 6–7 s.
* O mover el bucle mensual de POPs a C# o GDExtension, con una ganancia esperada de 10× o más en esos bucles.
  El año quedaría en ≈ 3–5 s, pero añade una cadena de compilación al proyecto.

## M3.2 — Almacén de POPs y estabilidad

```bash
# Pruebas del almacén: crear, leer/escribir, mover, promocionar, fusionar, borrar, reutilizar slots,
# guardar/cargar v4, enlace brigada ↔ Soldier POP, población de provincias y agregados nacionales
"$GODOT" --headless --path . res://tests/VPopStoreTest.tscn
```

**Último resultado:** `VPopStoreTest` 0 fallos · `VictoriaM3Test` 0 fallos (incluye el rechazo de partidas v3) ·
`VictoriaSmokeTest` 0 fallos · `VictoriaBalanceTest` 20, 30 y 50 años sin problemas.

### 20, 30 y 50 años (`VictoriaBalanceTest`, 0 problemas)

| Año | Pobl. (M) | Vida | Diario | Paro | Milit. | Conc. | Fábricas | Guerras | Brigadas máx. | Rebeldes (riesgo) | POPs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 740 | 0,80 | 0,36 | 0,03 | 0,41 | 0,30 | 227 | 28 | 91 | 0 (0) | 21.729 |
| 20 | 786 | 0,83 | 0,38 | 0,06 | 0,39 | 0,26 | 381 | 51 | 101 | 7 (2) | 22.430 |
| 30 | 842 | 0,77 | 0,33 | 0,09 | 0,24 | 0,37 | 511 | 70 | 147 | 3 (9) | 23.041 |
| 40 | 892 | 0,74 | 0,34 | 0,11 | 0,26 | 0,72 | 594 | 82 | 160 | 10 (14) | 23.615 |
| 50 | 939 | 0,70 | 0,31 | 0,14 | 0,47 | 1,19 | 605 | 92 | 130 | 26 (19) | 24.105 |

* La militancia queda acotada (0,24–0,47) sin deriva.
* La conciencia sigue a la alfabetización hacia un equilibrio: sin la relajación llegaba a 2,76 a los 50 años
  y seguía subiendo.
* No se fusionó ningún POP en 50 años: los traslados reutilizan el POP coincidente, así que no hay
  fragmentación.
* Tendencias a vigilar en M4: el paro sube despacio (0,03 → 0,14) y las rebeliones aumentan a partir de los
  40 años.

### Rendimiento: `c01f49b` frente a M3.2 (mismo equipo y misma partida, 10 años)

| Medida (s/año) | c01f49b | M3.2 | Cambio |
|---|---|---|---|
| **Total por año (media de 10 años)** | **10,51** | **8,22** | −22 % |
| Año 1 / año más lento | 8,9 / 11,8 | 6,3 / 9,4 | |
| Población (cubos + cierre de mes) | 3,15 | 1,96 | −38 % |
| Producción por provincia (RGO, artesanos, empleo) | 1,79 | 1,29 | −28 % |
| Movilidad | 1,28 | 0,98 | −24 % |
| Suministro militar | 1,19 | 0,96 | −20 % |
| Capa militar diaria | 2,98 | 2,65 | |
| Cierre de mes (media / máx. ms) | 125 / 176 | 106 / 190 | |
| Tick diario (media / máx. ms) | 24,5 / 87 | 18,8 / 81 | |

Cuando una optimización no podía cambiar resultados (cachés exactas, alias, códigos enteros), la huella de la
simulación quedó idéntica entre ejecuciones; así se comprobó cada paso.

### Objetivo < 8 s/año: no alcanzado (8,2 s)

Los tres mayores costes restantes (tramo de años 5–10):
1. Capa militar diaria: 2,65 s (suministro 0,96 · IA terrestre 0,64 · refuerzo 0,26 · armada 0,24 · movimiento 0,21).
2. Producción: 2,2 s (RGO/artesanos/empleo 1,29 · fábricas 0,33 · inversión y mercado mensuales).
3. Población: 1,96 s (≈6 µs por POP y mes, ≈21.700 POPs).

Después de pasar a estructura de arrays, el coste por POP lo dominan las operaciones del propio intérprete:
unas 45 lecturas y escrituras de arrays, unas 25 operaciones aritméticas y unas 8 llamadas a funciones
integradas por POP y mes. Las micro-optimizaciones posteriores ya daban ganancias del 1–2 %, dentro del ruido.

### ¿Hace falta C#/GDExtension? Informe (no se ha migrado nada)

* **Qué mover:**
  * `VPopulationSystem.process_province`: necesidades, consecuencias, deriva e issues.
  * `VProductionSystem.process_province` y `process_state_instance`.
  * `VMobilitySystem.process_province`.
  * Opcionalmente, el bucle por ejército de `VSupplySystem.daily`.
  
  Son funciones puras sobre arrays: el almacén ya está en estructura de arrays, así que el cambio es local.
* **API entre GDScript y C#:** el almacén (`VPopStore`) pasaría a ser un objeto C# con los mismos arrays
  como `float[]`/`int[]`, y GDScript seguiría accediendo por slot (`get_pop_details`, campos sueltos).
  Por provincia y mes se pasarían a C# los parámetros de país ya preparados: la matriz de necesidades, los
  impuestos, los modificadores y el contexto de mercado como arrays por índice de bien. Las reglas (tipos,
  promoción, issues) se cargarían una vez desde los mismos JSON.
* **Ganancia esperada:** del orden de 10–30× en esos bucles. Población, producción y movilidad (≈4,2 s/año)
  pasarían a ≈0,3 s, y el año a ≈4–5 s. Con el suministro, ≈3,5–4,5 s.
* **Coste:**
  * Hay que usar el editor y la exportación «.NET» de Godot (el ejecutable actual no tiene mono) y el SDK
    de .NET 8.
  * El juego exportado crece unos 70 MB por el runtime.
  * Las exportaciones web de Godot 4 con C# aún no están soportadas.
  * Habría que mantener dos lenguajes y pruebas cruzadas.
  * Una GDExtension en C++ evita el runtime, pero exige compilar por plataforma.
* **Recomendación:** la simulación ya está a ≈3 % del mínimo pedido y es determinista. Si el objetivo
  de 3–6 s/año es firme, merece la pena mover esos tres o cuatro bucles a C# con la API de arriba. Si basta con
  ≈8 s, no hace falta todavía. Pendiente de decisión.
