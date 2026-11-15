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
