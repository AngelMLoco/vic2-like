#!/usr/bin/env python3
"""Crea el mundo de PRUEBA `test_fantasy` (TEST ONLY — NOT AETHER LORE).

Sirve únicamente para probar el importador de mapas fantásticos y la carga multi-mundo: dos continentes y una
isla, un lago, varias zonas marítimas y tres países de prueba. No es Chronicles of Aether ni sustituye a sus
datos, que aporta el autor.

Uso (desde la raíz del repositorio):
    python tools/fantasy_map/make_test_fixture.py      # escribe source/ y los datos de autor del fixture
    python tools/fantasy_map/build_fantasy_world.py test_fantasy
"""
from __future__ import annotations

import json
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
WORLD = os.path.join(REPO, "data", "victoria_mode", "worlds", "test_fantasy")
W, H = 320, 180
LAND, SEA, LAKE = "ffffff", "1f4e79", "5b9bd5"
TAG = "TEST ONLY — NOT AETHER LORE"

# masas de tierra: (centro x, centro y, radio x, radio y, fase) · región por masa
BLOBS = [
    (85, 85, 62, 52, 0.3, "west"),
    (225, 70, 66, 42, 1.7, "east"),
    (230, 148, 26, 16, 2.9, "isle"),
]
REGIONS = [
    {"key": "west", "name": "Tierra de prueba Oeste", "color": "c0392b", "density": 1.0, "owner": "TFA", "culture": "test_culture_a", "religion": "test_faith_a"},
    {"key": "east", "name": "Tierra de prueba Este", "color": "2980b9", "density": 1.3, "owner": "TFB", "culture": "test_culture_b", "religion": "test_faith_b"},
    {"key": "isle", "name": "Isla de prueba", "color": "27ae60", "density": 0.8, "owner": "TFC", "culture": "test_culture_c", "religion": "test_faith_a"},
]


def rgb(h: str) -> tuple:
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def write_json(rel: str, obj) -> None:
    path = os.path.join(WORLD, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=1)
        fh.write("\n")


def main() -> None:
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
    mask = np.zeros((H, W, 3), dtype=np.uint8)
    mask[:] = rgb(SEA)
    regions = np.zeros((H, W, 3), dtype=np.uint8)
    for cx, cy, rx, ry, ph, reg in BLOBS:
        ang = np.arctan2((ys - cy) / ry, (xs - cx) / rx)
        r = np.hypot((xs - cx) / rx, (ys - cy) / ry)
        edge = 1.0 + 0.12 * np.sin(3 * ang + ph) + 0.07 * np.sin(7 * ang + 2 * ph)
        land = r < edge
        mask[land] = rgb(LAND)
        regions[land] = rgb(next(x for x in REGIONS if x["key"] == reg)["color"])
    # un lago en el continente oeste
    lake = np.hypot((xs - 70) / 9.0, (ys - 80) / 6.0) < 1.0
    mask[lake] = rgb(LAKE)
    src = os.path.join(WORLD, "source")
    os.makedirs(src, exist_ok=True)
    Image.fromarray(mask, "RGB").save(os.path.join(src, "land_mask.png"))
    Image.fromarray(regions, "RGB").save(os.path.join(src, "regions.png"))
    write_json("source/map_rules.json", {
        "_doc": f"{TAG}. Parámetros del importador (ver docs/FantasyMapPipeline.md).",
        "seed": 136, "width": W, "height": H,
        "mask_colors": {"land": LAND, "sea": SEA, "lake": LAKE},
        "target_land_provinces": 30, "target_sea_zones": 7,
        "min_province_px": 120, "max_province_px": 1600, "min_island_px": 6,
        "max_provinces_per_state": 4, "km2_per_px": 60.0, "border_noise": 0.35, "wrap_x": False,
    })
    write_json("source/regions.json", {"_doc": TAG, "regions": REGIONS})
    write_json("source/province_seeds.json", {"_doc": f"{TAG}. Semillas con clave estable.", "seeds": [
        {"key": "tfa_capital", "x": 95, "y": 70, "name": "Capital de prueba A"},
        {"key": "tfb_capital", "x": 220, "y": 60, "name": "Capital de prueba B"},
        {"key": "tfc_capital", "x": 230, "y": 148, "name": "Capital de prueba C"},
        {"key": "strait_west", "x": 150, "y": 95, "name": "Estrecho de prueba"},
    ]})
    write_json("source/adjacencies.json", {"_doc": TAG, "adjacencies": []})
    write_json("world.json", {
        "_doc": f"{TAG}. Fixture automático del importador y de la carga multi-mundo. Lo regenera tools/fantasy_map/make_test_fixture.py.",
        "id": "test_fantasy", "name": "Mundo de prueba", "description": TAG,
        "width": W, "height": H, "wrap_x": False, "default_scenario": "test_fantasy_1",
        "enabled": True, "test_only": True, "author": "", "version": "1",
        "generator": "tools/fantasy_map/build_fantasy_world.py", "forbidden_packs": ["prototype"],
    })
    write_json("cultures/cultures.json", {
        "_doc": TAG,
        "groups": [{"id": "test_group", "name": "Grupo de prueba", "magic_tradition": "common"}],
        "cultures": [
            {"id": "test_culture_a", "name": "Cultura de prueba A", "group": "test_group", "religion": "test_faith_a", "color": "c0392b"},
            {"id": "test_culture_b", "name": "Cultura de prueba B", "group": "test_group", "religion": "test_faith_b", "color": "2980b9"},
            {"id": "test_culture_c", "name": "Cultura de prueba C", "group": "test_group", "religion": "test_faith_a", "color": "27ae60"},
        ],
    })
    write_json("religions/religions.json", {"_doc": TAG, "religions": [
        {"id": "test_faith_a", "name": "Fe de prueba A", "group": "test", "color": "d4ac0d", "magic_attitude": "accepted"},
        {"id": "test_faith_b", "name": "Fe de prueba B", "group": "test", "color": "8e44ad", "magic_attitude": "regulated"},
    ]})
    def country(tag, name, color, culture, religion, gov, ideology):
        return {"tag": tag, "name": name, "color": color, "flag": {"pattern": "bicolor_h", "colors": [color, "ffffff"]},
                "capital": None, "primary_culture": culture, "accepted_cultures": [], "religion": religion,
                "government": gov, "ruling_party": {"name": "Partido de prueba", "ideology": ideology},
                "civilized": True, "prestige": 20, "treasury": 3000, "literacy": 0.2, "description": TAG,
                "technologies": [], "reforms": {}, "magic_branches": {"technology": 0, "economy": 0, "military": 0, "politics": 0}}
    write_json("countries/countries.json", {"_doc": TAG, "countries": [
        country("TFA", "País de prueba A", "c0392b", "test_culture_a", "test_faith_a", "monarquia_absoluta", "conservador"),
        country("TFB", "País de prueba B", "2980b9", "test_culture_b", "test_faith_b", "republica", "liberal"),
        country("TFC", "País de prueba C", "27ae60", "test_culture_c", "test_faith_a", "monarquia_constitucional", "conservador"),
    ]})
    write_json("history/start.json", {
        "_doc": TAG, "start_date": {"year": 1, "month": 1, "day": 1},
        "countries": {
            "TFA": {"brigades": 3, "ships": 2, "factory_levels": 1},
            "TFB": {"brigades": 3, "ships": 2, "factory_levels": 1},
            "TFC": {"brigades": 1, "ships": 1, "factory_levels": 0},
        },
        "alliances": [], "relations": [["TFA", "TFB", -20]], "wars": [],
    })
    print(f"fixture escrito en {WORLD} ({TAG})")


if __name__ == "__main__":
    main()
