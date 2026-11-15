# Segunda versión — Hoja de ruta

Filosofía: **Victoria II como esqueleto → Chronicles of Aether como juego final.**
Mecánicas y organización funcional inspiradas en Victoria II / HoD (y la filosofía de contenido
de GFM), con código, datos, gráficos y geografía propios (Natural Earth, dominio público).

## Estado por fase

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Auditoría, checkpoint git (`backup/pre-victoria-mode`, tag `checkpoint-pre-victoria-mode`), legacy aislado en `src/legacy` + `data/legacy` | ✅ |
| 1 | Menú principal (Nuevo / Cargar / Opciones / Salir) y selector de modo | ✅ |
| 2 | Mapamundi: 2.922 provincias, 1.060 estados, 389 zonas marítimas, 146 lagos; fronteras de país/estado/provincia/costa; cámara; minimapa; 12 mapmodes activos + 6 previstos | ✅ |
| 3 | Selección de nación estilo Victoria, ranking GP/secundarias, JUGAR | ✅ |
| 4 | Datos base: 89 naciones, 107 culturas, 18 religiones, cores, RGOs, terrenos | ✅ (base) |
| 5 | POPs: tipos, generación inicial, agregados ✅ · necesidades, empleo, promoción, migración ⏳ | 🟡 |
| 6 | Economía: RGO, bienes (catálogo de 49), fábricas por estado (datos ✅), artesanos, mercado interno→esfera→mundial, presupuesto completo, stockpile | ⏳ |
| 7 | Política: gobiernos/ideologías (datos ✅), partidos, elecciones, cámara alta, reformas por niveles, movimientos → rebeldes | ⏳ |
| 8 | Tecnología: árbol, investigación, inventos, base para magia (`magic_branches` ✅) | ⏳ |
| 9 | Diplomacia: relaciones, alianzas (datos ✅), influencia, esferas, crisis | ⏳ |
| 10 | Ejército físico: brigadas, Soldier POP, movimiento, supply, attrition, generales | ⏳ |
| 11 | Guerra: CB data-driven, justificación, ocupación, warscore, wargoals, paz | ⏳ |
| 12 | Armada: flotas, transporte naval real, bloqueos, combate naval | ⏳ |
| 13 | Eventos/decisiones GFM-like (scripted + condicionales, cadenas, flags) | ⏳ |
| 14 | Pulido: tooltips, ledger, rendimiento, saves | ⏳ |

## Milestone 1 (actual) — "esto es la base correcta"

Hecho: menú, selector de modo, mapamundi real con países/estados/provincias, fronteras, colores
nacionales, zoom, paneo, minimapa, mapmodes, selección de país desde el mapa, ranking, pantalla
de inicio, botón JUGAR, barra superior con 8 pestañas, panel de provincia, fecha año 136,
pausa y velocidades 1–5, guardado/carga con `save_version`.

Placeholders conscientes del milestone 1:
* Presupuesto simplificado (impuestos por estrato desde POPs reales; aranceles/deuda/banco a 0).
* Ejército y flota son recuentos (brigadas/barcos por país), aún no unidades en el mapa.
* Las pestañas Tecnología, Comercio, Diplomacia muestran datos reales disponibles y botones
  deshabilitados con la fase en la que se activan.
* Ideología de POPs inicial por estrato; militancia/conciencia constantes.
* Nombres de provincias: ciudades reales de Natural Earth (temporal, el mapa se sustituirá).

## Siguiente paso (milestone 2)

1. `economy/`: VMarketSystem (precios, oferta/demanda, interno→esfera→mundial),
   VProductionSystem (RGO por provincia, fábricas por instancia de estado, artesanos).
2. `population/`: necesidades life/everyday/luxury con compra real, empleo, promoción/democión, migración.
3. Presupuesto completo (ingresos/gastos reales, deuda, stockpile).
4. `politics/`: partidos por país, elecciones, cámara alta, reformas por niveles (datos en `reforms/`).
5. `technology/`: árbol data-driven + inventos.
