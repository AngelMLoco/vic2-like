#!/usr/bin/env python3
"""Importador de mapas fantásticos (M6) — convierte una geografía DISEÑADA en los datos del motor.

No inventa el mundo: parte de una máscara de tierra/mar/lagos dibujada por el autor y genera una partición en
provincias y zonas marítimas con fronteras orgánicas, estados provisionales (o por regiones del autor) y el
mismo formato que usa VWorldMap / VDataLoader (el del mundo terrestre).

Uso (desde la raíz del repositorio):
    python tools/fantasy_map/build_fantasy_world.py <world_id>
    python tools/fantasy_map/build_fantasy_world.py <world_id> --check        # valida la fuente, no escribe
    python tools/fantasy_map/build_fantasy_world.py <world_id> --allow-id-break

ENTRADA (autor) — data/victoria_mode/worlds/<id>/source/:
    map_rules.json         obligatorio: parámetros (semilla, nº de provincias y mares, tamaños, colores…)
    land_mask.png          obligatorio: tierra / mar / lago con los colores de map_rules.mask_colors
    terrain.png            opcional: colores → terreno (map_rules.terrain_colors)
    regions.png + regions.json  opcional: regiones del autor (nombre, densidad, dueño, cultura, religión)
    province_seeds.json    opcional: semillas con clave estable (capitales, provincias con nombre…)
    province_overrides.json opcional: datos por clave de provincia (nombre, dueño, cultura, RGO…)
    adjacencies.json       opcional: estrechos y pasos entre claves de provincia

BLOQUEO DE IDS (lo mantiene la herramienta; se versiona y no se borra) — worlds/<id>/ids.lock.json:
    clave estable → id y posición de cada semilla, versión del mapa y huella de la geometría.

SALIDA (generada; nunca se edita a mano) — worlds/<id>/:
    map/provinces.png  map/map.json  map/geometry.json  map/adjacencies.json
    provinces/provinces.json  provinces/sea_zones.json  states/states.json

Requiere: numpy, Pillow. Ver docs/FantasyMapPipeline.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import zlib

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
WORLDS = os.path.join(REPO, "data", "victoria_mode", "worlds")
NONE, LAND, SEA, LAKE = 0, 1, 2, 3
KIND = {LAND: "land", SEA: "sea", LAKE: "lake"}
PREFIX = {LAND: "L", SEA: "S", LAKE: "K"}
ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV",
         "XVI", "XVII", "XVIII", "XIX", "XX"]

DEFAULTS = {
    "seed": 1,
    "mask_colors": {"land": "ffffff", "sea": "1f4e79", "lake": "5b9bd5"},
    "target_land_provinces": 40,
    "target_sea_zones": 8,
    "min_province_px": 40,
    "max_province_px": 0,          # 0 = 4 × tamaño medio
    "min_island_px": 6,            # masas de tierra/agua menores: dato roto (error)
    "max_provinces_per_state": 4,
    "km2_per_px": 100.0,
    "border_noise": 0.35,          # amplitud de la deformación de fronteras (fracción del espaciado medio)
    "wrap_x": False,
    "terrain_colors": {},
    "default_terrain_weights": {"plains": 4, "farmlands": 3, "woods": 2, "hills": 2, "forest": 1, "mountains": 1},
    "rgo_by_terrain": {
        "plains": {"grain": 4, "cattle": 2, "wool": 1}, "farmlands": {"grain": 5, "fruit": 1, "cotton": 1},
        "woods": {"timber": 4, "furs": 1}, "forest": {"timber": 5}, "hills": {"iron": 2, "coal": 2, "wool": 2},
        "mountains": {"iron": 2, "precious_metal": 1, "coal": 2}, "steppe": {"cattle": 3, "wool": 2},
        "desert": {"sulphur": 1, "cattle": 1}, "jungle": {"tropical_wood": 3, "rubber": 1, "spices": 1},
        "marsh": {"cattle": 1, "grain": 1}, "tundra": {"furs": 2, "timber": 1}, "arctic": {"furs": 1},
    },
    "population_per_km2": {"plains": 30, "farmlands": 45, "woods": 18, "forest": 10, "hills": 20, "mountains": 8,
                           "steppe": 9, "desert": 3, "jungle": 12, "marsh": 10, "tundra": 2, "arctic": 0.5},
    "life_rating": {"farmlands": 33, "plains": 30, "woods": 27, "forest": 22, "hills": 25, "mountains": 18,
                    "steppe": 20, "desert": 12, "jungle": 16, "marsh": 18, "tundra": 10, "arctic": 6},
    "coastal_fish_chance": 0.12,
    "defaults": {"owner": "", "culture": "", "religion": ""},
    "names": {"province": "{region} {n}", "sea": "Mar {n}", "lake": "Lago {n}", "region": "Región {n}"},
}


class MapError(Exception):
    pass


def log(msg: str) -> None:
    print(msg, flush=True)


def stable_rand(*keys) -> float:
    h = zlib.crc32("|".join(str(k) for k in keys).encode("utf-8"))
    return (h & 0xFFFFFF) / float(0x1000000)


def weighted_pick(weights: dict, *keys) -> str:
    items = sorted(weights.items())
    total = sum(w for _, w in items)
    r = stable_rand(*keys) * total
    for k, w in items:
        r -= w
        if r < 0:
            return k
    return items[-1][0]


def hex_code(h: str) -> int:
    h = h.lstrip("#").lower()
    if len(h) != 6:
        raise MapError(f"color inválido «{h}» (se espera RRGGBB)")
    return int(h, 16)


def read_json(path: str, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def rgb_codes(path: str) -> np.ndarray:
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int64)
    return (a[..., 0] << 16) | (a[..., 1] << 8) | a[..., 2]


def describe_bad_colors(codes: np.ndarray, bad: np.ndarray, what: str) -> str:
    vals, counts = np.unique(codes[bad], return_counts=True)
    parts = []
    for v, c in list(zip(vals.tolist(), counts.tolist()))[:6]:
        ys, xs = np.nonzero((codes == v) & bad)
        parts.append(f"#{v:06x} ×{c} (p. ej. x={xs[0]}, y={ys[0]})")
    return f"{what}: {int(bad.sum())} píxeles con colores no declarados: " + ", ".join(parts)


# ------------------------------------------------------------------ rejilla
def neighbor_views(a: np.ndarray, wrap: bool, fill):
    """Vecinos 4-conexos de cada celda: (arriba, abajo, izquierda, derecha)."""
    H, W = a.shape
    up = np.full_like(a, fill); up[1:] = a[:-1]
    dn = np.full_like(a, fill); dn[:-1] = a[1:]
    if wrap:
        lf = np.roll(a, 1, axis=1); rt = np.roll(a, -1, axis=1)
    else:
        lf = np.full_like(a, fill); lf[:, 1:] = a[:, :-1]
        rt = np.full_like(a, fill); rt[:, :-1] = a[:, 1:]
    return up, dn, lf, rt


def label_equal(val: np.ndarray, wrap: bool) -> np.ndarray:
    """Componentes 4-conexas de celdas con el mismo valor (val < 0 se ignora). Etiqueta = índice mínimo.
    Grafo de aristas entre vecinos iguales + enganche al mínimo y compresión de punteros (O(log n) rondas)."""
    H, W = val.shape
    n = H * W
    flat = val.ravel()
    idx = np.arange(n, dtype=np.int64).reshape(H, W)
    us, vs = [], []
    pairs = [(idx[:, :-1], idx[:, 1:]), (idx[:-1, :], idx[1:, :])]
    if wrap:
        pairs.append((idx[:, -1:], idx[:, :1]))
    for a, b in pairs:
        a = a.ravel(); b = b.ravel()
        keep = (flat[a] == flat[b]) & (flat[a] >= 0)
        us.append(a[keep]); vs.append(b[keep])
    u = np.concatenate(us); v = np.concatenate(vs)
    parent = np.arange(n, dtype=np.int64)
    while True:
        pu = parent[u]; pv = parent[v]
        lo = np.minimum(pu, pv); hi = np.maximum(pu, pv)
        diff = lo != hi
        if not diff.any():
            break
        np.minimum.at(parent, hi[diff], lo[diff])
        while True:
            nxt = parent[parent]
            if np.array_equal(nxt, parent):
                break
            parent = nxt
    return np.where(flat >= 0, parent, -1).reshape(H, W)


def smooth_noise(H: int, W: int, cell: float, rng: np.random.Generator) -> np.ndarray:
    gh = int(math.ceil(H / cell)) + 2
    gw = int(math.ceil(W / cell)) + 2
    g = rng.uniform(-1.0, 1.0, size=(gh, gw))
    ys = np.arange(H) / cell
    xs = np.arange(W) / cell
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def voronoi(H: int, W: int, sx: np.ndarray, sy: np.ndarray, px: np.ndarray, py: np.ndarray, wrap: bool) -> np.ndarray:
    """Semilla más cercana a cada píxel (coordenadas deformadas) por jump flooding."""
    best = np.full((H, W), -1, dtype=np.int64)
    best[sy.astype(int), sx.astype(int)] = np.arange(sx.size)

    def dist(cand):
        c = np.where(cand >= 0, cand, 0)
        dx = px - sx[c]
        if wrap:
            dx = (dx + W / 2.0) % W - W / 2.0
        dy = py - sy[c]
        return np.where(cand >= 0, dx * dx + dy * dy, np.inf)

    dbest = dist(best)
    step = 1 << max(0, int(math.ceil(math.log2(max(H, W)))) - 1)
    steps = []
    while step >= 1:
        steps.append(step)
        step //= 2
    steps += [2, 1]  # JFA+2: corrige los errores residuales
    for st in steps:
        for oy in (-st, 0, st):
            for ox in (-st, 0, st):
                if (ox == 0 and oy == 0) or abs(oy) >= H or (abs(ox) >= W and not wrap):
                    continue
                cand = np.full_like(best, -1)
                ys_dst = slice(max(0, -oy), H - max(0, oy))
                ys_src = slice(max(0, oy), H - max(0, -oy))
                if wrap:
                    rolled = np.roll(best, -ox, axis=1)
                    cand[ys_dst] = rolled[ys_src]
                else:
                    xs_dst = slice(max(0, -ox), W - max(0, ox))
                    xs_src = slice(max(0, ox), W - max(0, -ox))
                    cand[ys_dst, xs_dst] = best[ys_src, xs_src]
                d = dist(cand)
                upd = d < dbest
                best[upd] = cand[upd]
                dbest[upd] = d[upd]
    return best


# ------------------------------------------------------------------ fuente
def load_source(world_dir: str) -> dict:
    src = os.path.join(world_dir, "source")
    rules_user = read_json(os.path.join(src, "map_rules.json"))
    if rules_user is None:
        raise MapError(f"falta {os.path.join(src, 'map_rules.json')}")
    rules = json.loads(json.dumps(DEFAULTS))
    for k, v in rules_user.items():
        if isinstance(v, dict) and isinstance(rules.get(k), dict) and k not in ("terrain_colors",):
            rules[k].update(v)
        else:
            rules[k] = v
    mask_path = os.path.join(src, "land_mask.png")
    if not os.path.exists(mask_path):
        raise MapError(f"falta {mask_path}")
    codes = rgb_codes(mask_path)
    H, W = codes.shape
    if rules.get("width") and int(rules["width"]) != W or rules.get("height") and int(rules["height"]) != H:
        raise MapError(f"land_mask.png mide {W}×{H} y map_rules declara {rules.get('width')}×{rules.get('height')}")
    if W < 16 or H < 16 or W > 16384 or H > 16384:
        raise MapError(f"dimensiones fuera de rango: {W}×{H}")
    kind = np.zeros((H, W), dtype=np.int8)
    mc = rules["mask_colors"]
    for name, k in (("land", LAND), ("sea", SEA), ("lake", LAKE)):
        kind[codes == hex_code(mc[name])] = k
    if (kind == NONE).any():
        raise MapError(describe_bad_colors(codes, kind == NONE, "land_mask.png"))
    if not (kind == LAND).any():
        raise MapError("land_mask.png no tiene tierra")
    if not (kind == SEA).any():
        raise MapError("land_mask.png no tiene mar")
    out = {"rules": rules, "kind": kind, "H": H, "W": W, "src": src}
    # terreno
    tpath = os.path.join(src, "terrain.png")
    if os.path.exists(tpath):
        tc = rgb_codes(tpath)
        if tc.shape != kind.shape:
            raise MapError("terrain.png no mide lo mismo que land_mask.png")
        names = sorted(set(rules["terrain_colors"].values()))
        tidx = np.full(kind.shape, -1, dtype=np.int64)
        for col, t in rules["terrain_colors"].items():
            tidx[tc == hex_code(col)] = names.index(t)
        bad = (tidx < 0) & (kind == LAND)
        if bad.any():
            raise MapError(describe_bad_colors(tc, bad, "terrain.png"))
        out["terrain"] = (tidx, names)
    # regiones
    rpath = os.path.join(src, "regions.png")
    rmeta = read_json(os.path.join(src, "regions.json"), {"regions": []})
    if os.path.exists(rpath):
        rc = rgb_codes(rpath)
        if rc.shape != kind.shape:
            raise MapError("regions.png no mide lo mismo que land_mask.png")
        regs = rmeta.get("regions", [])
        keys = [r["key"] for r in regs]
        if len(set(keys)) != len(keys):
            raise MapError("regions.json: claves de región repetidas")
        ridx = np.full(kind.shape, -1, dtype=np.int64)
        for i, r in enumerate(regs):
            ridx[rc == hex_code(r["color"])] = i
        bad = (ridx < 0) & (kind == LAND)
        if bad.any():
            raise MapError(describe_bad_colors(rc, bad, "regions.png (tierra sin región)"))
        out["regions"] = (ridx, regs)
    out["seeds"] = read_json(os.path.join(src, "province_seeds.json"), {"seeds": []}).get("seeds", [])
    out["overrides"] = read_json(os.path.join(src, "province_overrides.json"), {})
    out["adjacencies"] = read_json(os.path.join(src, "adjacencies.json"), {"adjacencies": []}).get("adjacencies", [])
    return out


# ------------------------------------------------------------------ partición
class Seed:
    __slots__ = ("key", "kind", "x", "y", "name", "auto", "locked_id")

    def __init__(self, key, kind, x, y, name="", auto=False, locked_id=0):
        self.key, self.kind, self.x, self.y = key, kind, int(x), int(y)
        self.name, self.auto, self.locked_id = name, auto, locked_id


def gather_seeds(S: dict, lock: dict) -> tuple[list, list]:
    kind, H, W = S["kind"], S["H"], S["W"]
    seeds, warnings = [], []
    used = {}
    for s in S["seeds"]:
        key = str(s["key"])
        x, y = int(s["x"]), int(s["y"])
        if key in used:
            raise MapError(f"province_seeds.json: clave repetida «{key}»")
        if not (0 <= x < W and 0 <= y < H):
            raise MapError(f"province_seeds.json: «{key}» fuera del mapa ({x}, {y})")
        if kind[y, x] == NONE:
            raise MapError(f"province_seeds.json: «{key}» sobre un píxel sin tipo")
        locked = next((p for p in lock.get("provinces", []) if p["key"] == key), None)
        seeds.append(Seed(key, int(kind[y, x]), x, y, s.get("name", ""), False, int(locked["id"]) if locked else 0))
        used[key] = True
    retired = []
    for p in lock.get("provinces", []):
        if p["key"] in used:
            continue
        if not p.get("auto", True):
            retired.append(p)  # semilla de autor que ya no está en province_seeds.json
            continue
        x, y = int(p["x"]), int(p["y"])
        want = {"land": LAND, "sea": SEA, "lake": LAKE}[p["kind"]]
        if 0 <= x < W and 0 <= y < H and kind[y, x] == want:
            seeds.append(Seed(p["key"], want, x, y, "", True, int(p["id"])))
            used[p["key"]] = True
        else:
            retired.append(p)
    return seeds, retired


def new_key(kindv: int, counters: dict) -> str:
    counters[PREFIX[kindv]] = counters.get(PREFIX[kindv], 0) + 1
    return f"{PREFIX[kindv]}{counters[PREFIX[kindv]]:04d}"


def ensure_component_seeds(S, seeds, counters, comp, kindv, rules):
    """Cada masa de tierra (o mar) separada necesita al menos una semilla; las demasiado pequeñas son error."""
    kind = S["kind"]
    lab = comp[kindv]
    ids, counts = np.unique(lab[lab >= 0], return_counts=True)
    has = set()
    for s in seeds:
        if s.kind == kindv:
            has.add(int(lab[s.y, s.x]))
    for cid, cnt in zip(ids.tolist(), counts.tolist()):
        if cnt < int(rules["min_island_px"]):
            y, x = divmod(cid, S["W"])
            raise MapError(f"dato desconectado: {KIND[kindv]} aislado de {cnt} px en x={x}, y={y} "
                           f"(mínimo {rules['min_island_px']}): bórralo o agrándalo en land_mask.png")
        if cid not in has:
            ys, xs = np.nonzero(lab == cid)
            j = len(xs) // 2
            order = np.lexsort((xs, ys))
            k = order[j]
            seeds.append(Seed(new_key(kindv, counters), kindv, xs[k], ys[k], "", True, 0))


def fill_seeds(S, seeds, counters, kindv, target, rng, density):
    kind = S["kind"]
    have = [s for s in seeds if s.kind == kindv]
    need = target - len(have)
    if need <= 0:
        return
    ys, xs = np.nonzero(kind == kindv)
    w = density[ys, xs] if density is not None else np.ones(xs.size)
    m = min(xs.size, max(200, target * 40))
    pick = rng.choice(xs.size, size=m, replace=False, p=w / w.sum())
    cx = xs[pick].astype(np.float64); cy = ys[pick].astype(np.float64); cw = w[pick]
    W = S["W"]
    wrap = bool(S["rules"]["wrap_x"])
    def d2(x, y):
        dx = np.abs(cx - x)
        if wrap:
            dx = np.minimum(dx, W - dx)
        return dx * dx + (cy - y) ** 2
    md = np.full(m, np.inf)
    for s in have:
        md = np.minimum(md, d2(s.x, s.y))
    for _ in range(need):
        score = md * cw
        j = int(np.argmax(score))
        if not np.isfinite(score[j]) and have:
            break
        seeds.append(Seed(new_key(kindv, counters), kindv, cx[j], cy[j], "", True, 0))
        md = np.minimum(md, d2(cx[j], cy[j]))
        have.append(seeds[-1])


def partition(S, seeds, kindv, px, py):
    kind = S["kind"]
    H, W = S["H"], S["W"]
    wrap = bool(S["rules"]["wrap_x"])
    sel = [i for i, s in enumerate(seeds) if s.kind == kindv]
    sx = np.array([seeds[i].x for i in sel], dtype=np.float64)
    sy = np.array([seeds[i].y for i in sel], dtype=np.float64)
    near = voronoi(H, W, sx, sy, px, py, wrap)
    owner = np.where(kind == kindv, np.array(sel, dtype=np.int64)[near], -1)
    # fragmentos: cada provincia conserva la componente de su semilla; el resto pasa a un vecino del mismo tipo
    for _ in range(64):
        lab = label_equal(owner, wrap)
        keep = {}
        for i in sel:
            s = seeds[i]
            if owner[s.y, s.x] == i:
                keep[i] = int(lab[s.y, s.x])
        valid = owner >= 0
        comp_ids, comp_counts = np.unique(lab[valid], return_counts=True)
        comp_owner = owner.ravel()[comp_ids]
        for cid, cnt, ow in sorted(zip(comp_ids.tolist(), comp_counts.tolist(), comp_owner.tolist()), key=lambda t: -t[1]):
            if ow not in keep:
                keep[ow] = cid
        keep_arr = np.full(len(seeds), -2, dtype=np.int64)
        for i, c in keep.items():
            keep_arr[i] = c
        bad = valid & (lab != keep_arr[np.where(valid, owner, 0)])
        if not bad.any():
            break
        good_owner = np.where(valid & ~bad, owner, -1)
        new = owner.copy()
        filled = np.zeros_like(bad)
        for nv in neighbor_views(good_owner, wrap, -1):
            take = bad & ~filled & (nv >= 0)
            new[take] = nv[take]
            filled |= take
        owner = new
    return owner


def build(world_id: str, check_only: bool = False, allow_id_break: bool = False, out_dir: str | None = None) -> dict:
    world_dir = os.path.join(WORLDS, world_id)
    if not os.path.isdir(world_dir):
        raise MapError(f"no existe el mundo {world_dir}")
    out_dir = out_dir or world_dir
    S = load_source(world_dir)
    rules, kind, H, W = S["rules"], S["kind"], S["H"], S["W"]
    wrap = bool(rules["wrap_x"])
    lock_path = os.path.join(out_dir, "ids.lock.json")
    lock = read_json(lock_path, {"provinces": [], "map_version": 0, "counters": {}})
    counters = dict(lock.get("counters", {}))
    rng = np.random.default_rng(int(rules["seed"]))
    report = {"warnings": []}

    comp = {k: label_equal(np.where(kind == k, 0, -1).astype(np.int64), wrap) for k in (LAND, SEA, LAKE)}
    seeds, retired = gather_seeds(S, lock)
    retired_land = [p for p in retired if p["kind"] == "land"]
    if retired_land and not allow_id_break:
        raise MapError("la nueva fuente elimina provincias terrestres con id asignado: "
                       + ", ".join(f"{p['key']} (id {p['id']})" for p in retired_land[:12])
                       + ". Cambiaría los ids de las provincias siguientes. Repite con --allow-id-break "
                         "(sube map_version y escribe ids_remap.json) o restaura la tierra/semilla.")
    ensure_component_seeds(S, seeds, counters, comp, LAND, rules)
    ensure_component_seeds(S, seeds, counters, comp, SEA, rules)
    # lagos: una provincia por lago (y semillas si un lago se queda sin ninguna)
    ensure_component_seeds(S, seeds, counters, comp, LAKE, {"min_island_px": 1})

    density = None
    if "regions" in S:
        ridx, regs = S["regions"]
        dens = np.array([float(r.get("density", 1.0)) for r in regs] + [1.0])
        density = dens[np.where(ridx >= 0, ridx, len(regs))]
    fill_seeds(S, seeds, counters, LAND, int(rules["target_land_provinces"]), rng, density)
    fill_seeds(S, seeds, counters, SEA, int(rules["target_sea_zones"]), rng, None)

    land_px = int((kind == LAND).sum())
    spacing = math.sqrt(land_px / max(1, int(rules["target_land_provinces"])))
    amp = float(rules["border_noise"]) * spacing
    nrng = np.random.default_rng(int(rules["seed"]) + 7)
    cell = max(4.0, spacing * 0.6)
    wx = smooth_noise(H, W, cell, nrng) + 0.5 * smooth_noise(H, W, cell / 2, nrng)
    wy = smooth_noise(H, W, cell, nrng) + 0.5 * smooth_noise(H, W, cell / 2, nrng)
    px = np.arange(W, dtype=np.float64)[None, :] + amp * wx
    py = np.arange(H, dtype=np.float64)[:, None] + amp * wy

    min_px = int(rules["min_province_px"])
    max_px = int(rules["max_province_px"]) or int(4 * land_px / max(1, int(rules["target_land_provinces"])))
    for it in range(4):
        owner = np.full((H, W), -1, dtype=np.int64)
        for k in (LAND, SEA):
            o = partition(S, seeds, k, px, py)
            owner = np.where(o >= 0, o, owner)
        # lagos: componente → semilla del lago
        for s_i, s in enumerate(seeds):
            if s.kind == LAKE:
                owner[comp[LAKE] == comp[LAKE][s.y, s.x]] = s_i
        sizes = np.bincount(owner[owner >= 0], minlength=len(seeds))
        changed = False
        drop = [i for i, s in enumerate(seeds) if s.kind == LAND and s.auto and s.locked_id == 0 and sizes[i] < min_px]
        if drop:
            seeds = [s for i, s in enumerate(seeds) if i not in set(drop)]
            changed = True
        else:
            for i, s in enumerate(seeds):
                if s.kind == LAND and sizes[i] > max_px:
                    ys, xs = np.nonzero(owner == i)
                    d = (xs - s.x) ** 2 + (ys - s.y) ** 2
                    j = int(np.argmax(d))
                    seeds.append(Seed(new_key(LAND, counters), LAND, xs[j], ys[j], "", True, 0))
                    changed = True
        if not changed:
            break
    sizes = np.bincount(owner[owner >= 0], minlength=len(seeds))
    for i, s in enumerate(seeds):
        if sizes[i] == 0:
            raise MapError(f"la semilla «{s.key}» ({s.x}, {s.y}) se quedó sin píxeles: muévela o bórrala")
        if s.kind == LAND and sizes[i] < min_px:
            report["warnings"].append(f"provincia «{s.key}» pequeña ({sizes[i]} px < {min_px}); es fija (semilla de autor o bloqueada)")

    # ---- ids estables
    locked_ids = {p["key"]: p for p in lock.get("provinces", [])}
    order = []
    for k in (LAND, SEA, LAKE):
        ks = [s for s in seeds if s.kind == k]
        ks.sort(key=lambda s: (0, locked_ids[s.key]["id"]) if s.key in locked_ids and locked_ids[s.key]["kind"] == KIND[k] else (1, s.key))
        order.extend(ks)
    new_id = {s.key: i + 1 for i, s in enumerate(order)}
    n_land = sum(1 for s in order if s.kind == LAND)
    n_sea = sum(1 for s in order if s.kind == SEA)
    n_lake = len(order) - n_land - n_sea
    land_moved = [k for k, p in locked_ids.items() if p["kind"] == "land" and k in new_id and new_id[k] != int(p["id"])]
    if land_moved and not allow_id_break:
        raise MapError("cambiarían ids de provincias terrestres existentes: " + ", ".join(
            f"{k} {locked_ids[k]['id']}→{new_id[k]}" for k in land_moved[:12]) + ". Usa --allow-id-break.")
    seed_index = {id(s): i for i, s in enumerate(seeds)}
    lut = np.zeros(len(seeds) + 1, dtype=np.int64)
    for s in order:
        lut[seed_index[id(s)]] = new_id[s.key]
    ID = lut[owner]

    # ---- geometría
    N = H * W
    flat = ID.ravel()
    n_total = len(order)
    cnt = np.bincount(flat, minlength=n_total + 1)
    xs_all = np.tile(np.arange(W), H)
    ys_all = np.repeat(np.arange(H), W)
    sx_ = np.bincount(flat, weights=xs_all, minlength=n_total + 1)
    sy_ = np.bincount(flat, weights=ys_all, minlength=n_total + 1)
    minx = np.full(n_total + 1, W); maxx = np.zeros(n_total + 1, dtype=np.int64)
    miny = np.full(n_total + 1, H); maxy = np.zeros(n_total + 1, dtype=np.int64)
    np.minimum.at(minx, flat, xs_all); np.maximum.at(maxx, flat, xs_all)
    np.minimum.at(miny, flat, ys_all); np.maximum.at(maxy, flat, ys_all)
    neighbors = {i: set() for i in range(1, n_total + 1)}
    for a, b in ((ID[:, :-1], ID[:, 1:]), (ID[:-1, :], ID[1:, :])) + (((ID[:, -1:], ID[:, :1]),) if wrap else ()):
        diff = a != b
        pairs = np.unique(np.stack([a[diff], b[diff]], axis=1), axis=0)
        for x, y in pairs.tolist():
            neighbors[x].add(y); neighbors[y].add(x)
    centers = {}
    for s in order:
        i = new_id[s.key]
        cx, cy = sx_[i] / cnt[i], sy_[i] / cnt[i]
        x, y = int(cx), int(cy)
        if not (0 <= x < W and 0 <= y < H and ID[y, x] == i):
            sub = ID[miny[i]:maxy[i] + 1, minx[i]:maxx[i] + 1]
            yy, xx = np.nonzero(sub == i)
            j = int(np.argmin((xx + minx[i] - cx) ** 2 + (yy + miny[i] - cy) ** 2))
            x, y = int(xx[j] + minx[i]), int(yy[j] + miny[i])
        centers[i] = (x, y)
    km2_px = float(rules["km2_per_px"])
    # distancia a la costa (canal B): dilataciones sucesivas (tope 64 px)
    water = ID >= n_land + 1
    dist = np.full((H, W), 64, dtype=np.int64)
    front = np.zeros((H, W), dtype=bool)
    for nv in neighbor_views(water, wrap, False):
        front |= nv != water
    dist[front] = 0
    reached = front.copy()
    for d in range(1, 64):
        grow = np.zeros_like(reached)
        for nv in neighbor_views(reached, wrap, False):
            grow |= nv
        grow &= ~reached
        if not grow.any():
            break
        dist[grow] = d
        reached |= grow

    # ---- terreno, regiones, datos de provincia
    terr = {}
    if "terrain" in S:
        tidx, tnames = S["terrain"]
        lp = (flat >= 1) & (flat <= n_land)
        tc = np.bincount(flat[lp] * len(tnames) + tidx.ravel()[lp], minlength=(n_land + 1) * len(tnames)).reshape(n_land + 1, len(tnames))
        for s in order[:n_land]:
            terr[s.key] = tnames[int(np.argmax(tc[new_id[s.key]]))]
    else:
        for s in order[:n_land]:
            terr[s.key] = weighted_pick(rules["default_terrain_weights"], "terrain", s.key)
    region_of = {}
    regions = []
    if "regions" in S:
        ridx, regs = S["regions"]
        lp = (flat >= 1) & (flat <= n_land)
        rc = np.bincount(flat[lp] * len(regs) + ridx.ravel()[lp], minlength=(n_land + 1) * len(regs)).reshape(n_land + 1, len(regs))
        regions = [dict(r) for r in regs]
        for s in order[:n_land]:
            region_of[s.key] = int(np.argmax(rc[new_id[s.key]]))
    else:
        # sin regiones del autor: una región provisional por masa de tierra (determinista)
        land_lab = comp[LAND]
        comps = sorted({int(land_lab[s.y, s.x]) for s in order[:n_land]})
        regions = [{"key": f"region_{j + 1}", "name": rules["names"]["region"].format(n=j + 1)} for j in range(len(comps))]
        for s in order[:n_land]:
            region_of[s.key] = comps.index(int(land_lab[s.y, s.x]))
    defaults = rules["defaults"]
    ov = S["overrides"]
    for k in ov:
        if k not in new_id:
            raise MapError(f"province_overrides.json: clave desconocida «{k}»")
    provinces_out = []
    per_region_n = {}
    for s in order[:n_land]:
        i = new_id[s.key]
        reg = regions[region_of[s.key]]
        per_region_n[region_of[s.key]] = per_region_n.get(region_of[s.key], 0) + 1
        terrain = terr[s.key]
        coastal = any(n > n_land and n <= n_land + n_sea for n in neighbors[i])
        if coastal and stable_rand("fish", s.key) < float(rules["coastal_fish_chance"]) and terrain != "mountains":
            rgo = "fish"
        else:
            rgo = weighted_pick(rules["rgo_by_terrain"].get(terrain, {"grain": 1}), "rgo", s.key)
        area = int(cnt[i] * km2_px)
        pop = area * float(rules["population_per_km2"].get(terrain, 10)) * (0.7 + 0.6 * stable_rand("pop", s.key))
        name = s.name or rules["names"]["province"].format(region=reg.get("name", ""), n=per_region_n[region_of[s.key]])
        po = {
            "id": i, "name": name, "state": 0,
            "owner": reg.get("owner", defaults.get("owner", "")),
            "culture": reg.get("culture", defaults.get("culture", "")),
            "religion": reg.get("religion", defaults.get("religion", "")),
            "terrain": terrain, "rgo": rgo,
            "life_rating": int(rules["life_rating"].get(terrain, 25) + stable_rand("life", s.key) * 8 - 3),
            "population": int(max(500, pop) // 10 * 10),
            "infrastructure": 0,
            "key": s.key,
        }
        for f, v in ov.get(s.key, {}).items():
            po[f] = v
        provinces_out.append(po)
    # nombres repetidos → sufijo
    seen = {}
    for po in provinces_out:
        seen.setdefault(po["name"], []).append(po)
    for nm, lst in seen.items():
        for j, po in enumerate(lst[1:], start=2):
            po["name"] = f"{nm} {ROMAN[min(j, 20)]}"

    # ---- estados: por región, en trozos de max_provinces_per_state contiguos (BFS determinista)
    max_per = int(rules["max_provinces_per_state"])
    states_out = []
    by_region = {}
    for po in provinces_out:
        by_region.setdefault(region_of[po["key"]], []).append(po["id"])
    pos = {po["id"]: po for po in provinces_out}
    for r in sorted(by_region):
        ids = sorted(by_region[r])
        left = set(ids)
        parts = []
        while left:
            start = min(left)
            part, queue = [start], [start]
            left.discard(start)
            while queue and len(part) < max_per:
                cur = queue.pop(0)
                for nb in sorted(neighbors[cur]):
                    if nb in left and len(part) < max_per:
                        left.discard(nb); part.append(nb); queue.append(nb)
            parts.append(sorted(part))
        base = regions[r].get("name", f"Región {r + 1}")
        for j, part in enumerate(parts):
            sid = len(states_out) + 1
            name = base if len(parts) == 1 else f"{base} {ROMAN[min(j + 1, 20)]}"
            states_out.append({"id": sid, "name": name, "provinces": part, "region": regions[r].get("key", "")})
            for p in part:
                pos[p]["state"] = sid

    # ---- mares y lagos
    sea_out = []
    n_s = n_k = 0
    for s in order[n_land:]:
        if s.kind == SEA:
            n_s += 1
            nm = s.name or rules["names"]["sea"].format(n=n_s)
        else:
            n_k += 1
            nm = s.name or rules["names"]["lake"].format(n=n_k)
        sea_out.append({"id": new_id[s.key], "kind": KIND[s.kind], "name": nm, "key": s.key})

    # ---- adyacencias del autor
    adjacencies = []
    for a in S["adjacencies"]:
        for k in (a["a"], a["b"]):
            if k not in new_id:
                raise MapError(f"adjacencies.json: clave desconocida «{k}»")
        ia, ib = new_id[a["a"]], new_id[a["b"]]
        if ib not in neighbors[ia]:
            adjacencies.append({"a": ia, "b": ib, "type": a.get("type", "sea_strait"), "name": a.get("name", "")})

    # ---- conectividad marítima (aviso: mares interiores separados)
    sea_ids = [new_id[s.key] for s in order if s.kind == SEA]
    extra = {}
    for a in adjacencies:
        extra.setdefault(a["a"], set()).add(a["b"]); extra.setdefault(a["b"], set()).add(a["a"])
    if sea_ids:
        seen_s = {sea_ids[0]}
        stack = [sea_ids[0]]
        while stack:
            c = stack.pop()
            for nb in neighbors[c] | extra.get(c, set()):
                if nb in sea_ids and nb not in seen_s:
                    seen_s.add(nb); stack.append(nb)
        if len(seen_s) != len(sea_ids):
            report["warnings"].append(f"{len(sea_ids) - len(seen_s)} zonas marítimas no conectan con el océano principal "
                                      "(mar interior): declara un estrecho en source/adjacencies.json si debe haber paso")

    geometry = []
    for s in order:
        i = new_id[s.key]
        x, y = centers[i]
        geometry.append({
            "id": i, "kind": KIND[s.kind], "center": [x, y],
            "bbox": [int(minx[i]), int(miny[i]), int(maxx[i]), int(maxy[i])],
            "area_px": int(cnt[i]), "area_km2": int(cnt[i] * km2_px),
            "lonlat": [round(x / W * 360.0 - 180.0, 2), round(90.0 - y / H * 180.0, 2)],
            "neighbors": sorted(neighbors[i]),
        })
    rgb = np.zeros((H, W, 3), dtype=np.uint8)
    rgb[..., 0] = (ID & 0xFF).astype(np.uint8)
    rgb[..., 1] = ((ID >> 8) & 0xFF).astype(np.uint8)
    rgb[..., 2] = np.clip(dist, 0, 255).astype(np.uint8)
    ghash = hashlib.sha1(ID.astype(np.int32).tobytes() + json.dumps(geometry, sort_keys=True).encode()
                         + json.dumps(adjacencies, sort_keys=True).encode()).hexdigest()
    old_version = int(lock.get("map_version", 0))
    map_version = old_version if lock.get("geometry_hash") == ghash and old_version > 0 else old_version + 1
    meta = {
        "width": W, "height": H,
        "projection": {"type": "none"},
        "id_encoding": "id = R + G*256 ; B = distancia a la costa en píxeles (0..64)",
        "land_count": n_land, "sea_count": n_sea, "lake_count": n_lake,
        "first_sea_id": n_land + 1, "first_lake_id": n_land + n_sea + 1,
        "wrap_x": wrap, "map_version": map_version,
        "source": f"worlds/{world_id}/source/ (autor)",
        "generator": "tools/fantasy_map/build_fantasy_world.py",
        "generated": "NO EDITAR: regenerar desde source/",
    }
    report.update({"land": n_land, "sea": n_sea, "lake": n_lake, "states": len(states_out), "map_version": map_version,
                   "geometry_hash": ghash, "retired": [p["key"] for p in retired], "ids": new_id,
                   "sizes": [int(cnt[new_id[s.key]]) for s in order[:n_land]]})
    if check_only:
        return report

    def dump(rel, obj, compact=False):
        path = os.path.join(out_dir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            if compact:
                fh.write("[\n" + ",\n".join(json.dumps(o, ensure_ascii=False, separators=(",", ":")) for o in obj) + "\n]\n")
            else:
                json.dump(obj, fh, ensure_ascii=False, indent=1)
                fh.write("\n")

    os.makedirs(os.path.join(out_dir, "map"), exist_ok=True)
    Image.fromarray(rgb, "RGB").save(os.path.join(out_dir, "map", "provinces.png"), optimize=True)
    with open(os.path.join(out_dir, "map", "provinces.png.import"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write('[remap]\n\nimporter="keep"\n')
    dump("map/map.json", meta)
    dump("map/geometry.json", geometry, compact=True)
    dump("map/adjacencies.json", adjacencies)
    order_keys = ["id", "name", "state", "owner", "culture", "religion", "terrain", "rgo", "life_rating",
                  "population", "infrastructure", "key"]
    dump("provinces/provinces.json", [{k: po[k] for k in order_keys if k in po} for po in provinces_out], compact=True)
    dump("provinces/sea_zones.json", sea_out, compact=True)
    dump("states/states.json", states_out, compact=True)
    new_lock = {
        "_doc": "Bloqueo de ids estables. Lo mantiene tools/fantasy_map/build_fantasy_world.py: versionar y no editar a mano.",
        "map_version": map_version, "geometry_hash": ghash, "counters": counters,
        "provinces": [{"key": s.key, "kind": KIND[s.kind], "id": new_id[s.key], "x": s.x, "y": s.y, "auto": s.auto} for s in order],
    }
    if retired or land_moved:
        remap = {"_doc": "ids que cambiaron en la regeneración (para migrar historia, eventos y núcleos)",
                 "from_version": old_version, "to_version": map_version,
                 "retired": [{"key": p["key"], "old_id": p["id"]} for p in retired],
                 "moved": [{"key": k, "old_id": int(locked_ids[k]["id"]), "new_id": new_id[k]} for k, p in locked_ids.items()
                           if k in new_id and new_id[k] != int(p["id"])]}
        dump("ids_remap.json", remap)
    dump("ids.lock.json", new_lock)
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("world")
    ap.add_argument("--check", action="store_true", help="valida la fuente sin escribir")
    ap.add_argument("--allow-id-break", action="store_true", help="permite eliminar o renumerar provincias terrestres")
    args = ap.parse_args()
    try:
        r = build(args.world, args.check, args.allow_id_break)
    except MapError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    log(f"mundo {args.world}: {r['land']} provincias terrestres, {r['sea']} zonas marítimas, {r['lake']} lagos, "
        f"{r['states']} estados · mapa v{r['map_version']}" + (" (solo validación)" if args.check else ""))
    sz = sorted(r["sizes"])
    if sz:
        log(f"tamaño de provincia (px): mín {sz[0]} · mediana {sz[len(sz) // 2]} · máx {sz[-1]}")
    for w in r["warnings"]:
        log(f"AVISO: {w}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
