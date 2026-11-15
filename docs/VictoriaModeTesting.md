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

Rendimiento (Godot 4.4.1, Ryzen + RX 6800, headless):

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
