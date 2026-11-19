"""Pruebas del importador de mapas fantásticos (M6). Trabajan sobre copias temporales del fixture test_fantasy.

    python -m unittest tests/tools/test_fantasy_map.py -v
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "fantasy_map"))
import build_fantasy_world as bfw  # noqa: E402

FIXTURE = os.path.join(REPO, "data", "victoria_mode", "worlds", "test_fantasy")
SEA = (0x1f, 0x4e, 0x79)
LAND = (255, 255, 255)


def jload(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def jsave(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)


class FantasyMapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="fmap_")
        self.world = os.path.join(self.tmp, "w")
        os.makedirs(self.world)
        shutil.copytree(os.path.join(FIXTURE, "source"), os.path.join(self.world, "source"))
        self._old = bfw.WORLDS
        bfw.WORLDS = self.tmp

    def tearDown(self):
        bfw.WORLDS = self._old
        shutil.rmtree(self.tmp, ignore_errors=True)

    def mask(self):
        return np.array(Image.open(os.path.join(self.world, "source", "land_mask.png")).convert("RGB"))

    def save_mask(self, a):
        Image.fromarray(a, "RGB").save(os.path.join(self.world, "source", "land_mask.png"))

    def paint_regions(self, ys, xs, color="27ae60"):
        p = os.path.join(self.world, "source", "regions.png")
        r = np.array(Image.open(p).convert("RGB"))
        r[ys, xs] = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))
        Image.fromarray(r, "RGB").save(p)

    def load(self, rel):
        with open(os.path.join(self.world, rel), encoding="utf-8") as fh:
            return json.load(fh)

    def lock_ids(self):
        return {p["key"]: (p["kind"], p["id"]) for p in self.load("ids.lock.json")["provinces"]}

    # ------------------------------------------------------------------
    def test_output_format(self):
        r = bfw.build("w")
        meta = self.load("map/map.json")
        geo = self.load("map/geometry.json")
        self.assertEqual([g["id"] for g in geo], list(range(1, len(geo) + 1)), "ids contiguos")
        self.assertEqual(meta["first_sea_id"], r["land"] + 1)
        self.assertEqual(meta["first_lake_id"], r["land"] + r["sea"] + 1)
        self.assertTrue(all(g["kind"] == "land" for g in geo[:r["land"]]))
        self.assertGreaterEqual(r["sea"], 4, "varias zonas marítimas, no un océano único")
        provs = self.load("provinces/provinces.json")
        states = self.load("states/states.json")
        in_states = sorted(p for s in states for p in s["provinces"])
        self.assertEqual(in_states, list(range(1, r["land"] + 1)), "cada provincia terrestre en un estado")
        for k in ("id", "name", "state", "owner", "culture", "religion", "terrain", "rgo", "life_rating", "population"):
            self.assertIn(k, provs[0])
        img = np.asarray(Image.open(os.path.join(self.world, "map", "provinces.png")).convert("RGB")).astype(int)
        ids = np.unique(img[..., 0] + img[..., 1] * 256)
        self.assertEqual(ids.tolist(), list(range(1, len(geo) + 1)), "cada id tiene píxeles y no hay píxeles sin id")

    def test_deterministic(self):
        r1 = bfw.build("w")
        h1 = r1["geometry_hash"]
        r2 = bfw.build("w")
        self.assertEqual(r2["geometry_hash"], h1)
        self.assertEqual(r2["map_version"], r1["map_version"], "regenerar sin cambios no sube la versión")

    def test_stable_ids_when_land_added(self):
        bfw.build("w")
        before = self.lock_ids()
        a = self.mask()
        ys, xs = np.mgrid[150:168, 20:44]
        a[ys, xs] = LAND  # isla nueva en el suroeste
        self.save_mask(a)
        self.paint_regions(ys, xs)
        r = bfw.build("w")
        after = self.lock_ids()
        land_before = {k: v for k, v in before.items() if v[0] == "land"}
        for k, v in land_before.items():
            self.assertEqual(after[k], v, f"la provincia terrestre {k} conserva su id")
        self.assertGreater(r["land"], len(land_before), "la isla nueva añade provincias al final")
        self.assertEqual(r["map_version"], 2, "la geometría cambió: map_version sube")

    def test_authored_seed_keys_survive(self):
        bfw.build("w")
        ids = self.lock_ids()
        self.assertIn("tfa_capital", ids)
        provs = {p["key"]: p for p in self.load("provinces/provinces.json")}
        self.assertEqual(provs["tfa_capital"]["name"], "Capital de prueba A")
        self.assertEqual(provs["tfa_capital"]["owner"], "TFA")

    def test_removing_land_requires_id_break(self):
        bfw.build("w")
        a = self.mask()
        a[125:175, 195:265] = SEA  # hunde la isla de prueba
        self.save_mask(a)
        seeds_p = os.path.join(self.world, "source", "province_seeds.json")
        seeds = jload(seeds_p)
        seeds["seeds"] = [s for s in seeds["seeds"] if s["key"] != "tfc_capital"]
        jsave(seeds_p, seeds)
        with self.assertRaises(bfw.MapError) as cm:
            bfw.build("w")
        self.assertIn("--allow-id-break", str(cm.exception))
        r = bfw.build("w", allow_id_break=True)
        self.assertEqual(r["map_version"], 2)
        remap = self.load("ids_remap.json")
        self.assertTrue(remap["retired"], "informe de ids retirados para migrar la historia")

    def test_invalid_color(self):
        a = self.mask()
        a[10, 10] = (255, 0, 255)
        self.save_mask(a)
        with self.assertRaises(bfw.MapError) as cm:
            bfw.build("w", check_only=True)
        self.assertIn("#ff00ff", str(cm.exception))

    def test_empty_land(self):
        a = self.mask()
        a[:] = SEA
        self.save_mask(a)
        with self.assertRaises(bfw.MapError) as cm:
            bfw.build("w", check_only=True)
        self.assertIn("no tiene tierra", str(cm.exception))

    def test_speck_island_is_bad_data(self):
        a = self.mask()
        a[5, 300] = LAND  # 1 px de tierra
        self.save_mask(a)
        self.paint_regions(np.array([5]), np.array([300]))
        with self.assertRaises(bfw.MapError) as cm:
            bfw.build("w", check_only=True)
        self.assertIn("desconectado", str(cm.exception))

    def test_dimension_mismatch(self):
        rules_p = os.path.join(self.world, "source", "map_rules.json")
        rules = jload(rules_p)
        rules["width"] = 999
        jsave(rules_p, rules)
        with self.assertRaises(bfw.MapError):
            bfw.build("w", check_only=True)


if __name__ == "__main__":
    unittest.main()
