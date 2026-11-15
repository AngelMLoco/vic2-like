#!/usr/bin/env python3
"""Generador del mapamundi de la "Segunda versión" (modo Victoria).

Construye, a partir de datos de Natural Earth (dominio público), el mapa de IDs
de provincias y los ficheros de datos de provincias, estados y zonas marítimas.

Uso (desde la raíz del repositorio):
    python tools/map_import/build_world.py            # descarga si falta y genera
    python tools/map_import/build_world.py --offline  # usa solo la caché

Salidas (data/victoria_mode/):
    map/provinces.png      R,G = id de provincia (16 bits); B = distancia a costa
    map/map.json           metadatos (tamaño, proyección, recuentos, fuentes)
    map/geometry.json      geometría derivada por id: tipo, centroide, bbox, área, vecinos
    map/adjacencies.json   estrechos y pasos explícitos (además de la vecindad por píxel)
    provinces/provinces.json   datos de juego iniciales por provincia terrestre
    provinces/sea_zones.json   nombres de zonas marítimas y lagos
    states/states.json         estados (agrupaciones de provincias)

La geometría (map/*) está separada de los datos de juego (provinces/, states/):
cambiar el propietario de una provincia nunca toca el PNG.
Requiere: numpy, Pillow.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
import urllib.request
import zlib

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(HERE, ".cache")
DATA = os.path.join(ROOT, "data", "victoria_mode")
NE_BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
SOURCES = {
    "admin1": "ne_10m_admin_1_states_provinces_lakes.geojson",
    "regions": "ne_50m_geography_regions_polys.geojson",
    "marine": "ne_50m_geography_marine_polys.geojson",
    "places": "ne_10m_populated_places_simple.geojson",
}
TERRAINS = ["plains", "farmlands", "woods", "forest", "hills", "mountains", "steppe",
            "desert", "jungle", "marsh", "tundra", "arctic"]
T_INDEX = {t: i + 1 for i, t in enumerate(TERRAINS)}  # 0 = templado sin definir
LAND, SEA, LAKE = "land", "sea", "lake"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------- utilidades
def load_geojson(key: str, offline: bool) -> dict:
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, SOURCES[key])
    if not os.path.exists(path):
        if offline:
            sys.exit(f"Falta {path} y se pidió --offline")
        log(f"descargando {SOURCES[key]}")
        urllib.request.urlretrieve(NE_BASE + SOURCES[key], path)
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def stable_rand(*keys) -> float:
    """Aleatorio determinista en [0,1) a partir de claves."""
    h = zlib.crc32("|".join(str(k) for k in keys).encode("utf-8"))
    return (h & 0xFFFFFF) / float(0x1000000)


def weighted_pick(weights: dict, *keys) -> str:
    total = sum(weights.values())
    r = stable_rand(*keys) * total
    acc = 0.0
    for k, w in weights.items():
        acc += w
        if r < acc:
            return k
    return next(iter(weights))


def in_box(box, lon, lat) -> bool:
    return box[0] <= lon <= box[2] and box[1] <= lat <= box[3]


ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII",
         "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"]


class Projection:
    """Proyección cilíndrica de Miller recortada en latitud."""

    def __init__(self, width: int, lat_top: float, lat_bottom: float):
        self.W = width
        self.lat_top = lat_top
        self.lat_bottom = lat_bottom
        self.y_top = self.miller(lat_top)
        self.y_bot = self.miller(lat_bottom)
        self.H = int(round(width * (self.y_top - self.y_bot) / (2 * math.pi)))

    @staticmethod
    def miller(lat):
        lat = max(-89.0, min(89.0, lat))
        return 1.25 * math.log(math.tan(math.pi / 4 + 0.4 * math.radians(lat)))

    def xy(self, lon, lat):
        x = (lon + 180.0) / 360.0 * self.W
        y = (self.y_top - self.miller(lat)) / (self.y_top - self.y_bot) * self.H
        return x, y

    def lat_of_row(self, rows):
        yy = self.y_top - (np.asarray(rows, dtype=np.float64) + 0.5) / self.H * (self.y_top - self.y_bot)
        return np.degrees((np.arctan(np.exp(yy / 1.25)) - math.pi / 4) / 0.4)

    def lon_of_col(self, cols):
        return (np.asarray(cols, dtype=np.float64) + 0.5) / self.W * 360.0 - 180.0


def rings_of(geom):
    if geom is None:
        return []
    if geom["type"] == "Polygon":
        return [geom["coordinates"]]
    if geom["type"] == "MultiPolygon":
        return geom["coordinates"]
    return []


def raster_features(proj, features, value_of, mode="I", order_key=None):
    """Rasteriza polígonos (con agujeros) a una imagen de enteros."""
    img = Image.new(mode, (proj.W, proj.H), 0)
    draw = ImageDraw.Draw(img)
    items = list(features)
    if order_key:
        items.sort(key=order_key, reverse=True)
    for feat in items:
        val = value_of(feat)
        if val is None:
            continue
        for poly in rings_of(feat.get("geometry")):
            if not poly:
                continue
            outer = [proj.xy(lon, lat) for lon, lat in poly[0]]
            if len(outer) >= 3:
                draw.polygon(outer, fill=val)
            for hole in poly[1:]:
                pts = [proj.xy(lon, lat) for lon, lat in hole]
                if len(pts) >= 3:
                    draw.polygon(pts, fill=0)
    return np.array(img, dtype=np.int32)


# ------------------------------------------------- crecimiento de regiones
class Grower:
    """Relleno aleatorio multi-semilla sobre una rejilla (con wrap horizontal).

    Cada píxel 'rellenable' tiene un grupo (allowed_group >= 0). Una etiqueta solo
    puede crecer hacia píxeles de su mismo grupo. El crecimiento probabilístico
    produce fronteras orgánicas en lugar de rectas de Voronoi.
    """

    def __init__(self, W, H, rng):
        self.W, self.H, self.rng = W, H, rng

    def neighbors(self, idx):
        W, H = self.W, self.H
        x = idx % W
        left = np.where(x == 0, idx + W - 1, idx - 1)
        right = np.where(x == W - 1, idx - W + 1, idx + 1)
        up = np.where(idx >= W, idx - W, -1)
        down = np.where(idx < W * (H - 1), idx + W, -1)
        return np.stack([left, right, up, down], axis=1)

    def grow(self, labels, group, label_group, p=0.6, seeds=None):
        """labels: int32 plano (-1 rellenable sin asignar, -2 no rellenable)."""
        rng = self.rng
        if seeds is None:
            seeds = np.nonzero(labels >= 0)[0]
        frontier = self.neighbors(seeds).ravel()
        frontier = frontier[frontier >= 0]
        frontier = np.unique(frontier[labels[frontier] == -1])
        it = 0
        while frontier.size:
            it += 1
            nb = self.neighbors(frontier)
            nbl = np.where(nb >= 0, labels[np.clip(nb, 0, None)], -1)
            valid = nbl >= 0
            g = group[frontier][:, None]
            valid &= label_group[np.clip(nbl, 0, None)] == g
            pri = rng.random(nb.shape)
            pri[~valid] = -1.0
            pick = np.argmax(pri, axis=1)
            has = valid.any(axis=1)
            accept = has & (rng.random(frontier.size) < p)
            chosen = nbl[np.arange(frontier.size), pick]
            newly = frontier[accept]
            labels[newly] = chosen[accept]
            waiting = frontier[has & ~accept]
            nxt = self.neighbors(newly).ravel()
            nxt = nxt[nxt >= 0]
            nxt = nxt[labels[nxt] == -1]
            frontier = np.unique(np.concatenate([nxt, waiting]))
        return it


def grid_spaced_pick(idx, W, cell):
    """Elige como mucho un índice por celda de 'cell' píxeles."""
    x = idx % W
    y = idx // W
    key = (y // cell) * (W // cell + 1) + (x // cell)
    _, first = np.unique(key, return_index=True)
    return idx[first]


def fill_regions(grower, labels, group, label_group_list, seeds_list, min_island_cell=14):
    """Crece desde semillas y crea etiquetas nuevas para componentes inalcanzados."""
    W = grower.W
    for lab, s in enumerate(seeds_list):
        labels[s] = lab
    label_group = np.array(label_group_list + [-9], dtype=np.int64)
    grower.grow(labels, group, label_group)
    rounds = 0
    while True:
        left = np.nonzero(labels == -1)[0]
        if left.size == 0 or rounds > 40:
            break
        rounds += 1
        picks = grid_spaced_pick(left, W, min_island_cell)
        start = len(label_group_list)
        for i, s in enumerate(picks):
            labels[s] = start + i
            label_group_list.append(int(group[s]))
            seeds_list.append(int(s))
        label_group = np.array(label_group_list + [-9], dtype=np.int64)
        grower.grow(labels, group, label_group, seeds=picks)
    return label_group_list, seeds_list


def relax(grower, labels_init, group, label_group_list, seeds, iterations=2):
    """Iteraciones tipo Lloyd: mueve cada semilla al centroide de su región."""
    W = grower.W
    labels = labels_init.copy()
    fill_regions(grower, labels, group, label_group_list, seeds)
    for _ in range(iterations):
        n = len(label_group_list)
        idx = np.nonzero(labels >= 0)[0]
        lab = labels[idx]
        cnt = np.bincount(lab, minlength=n).astype(np.float64)
        sx = np.bincount(lab, weights=(idx % W).astype(np.float64), minlength=n)
        sy = np.bincount(lab, weights=(idx // W).astype(np.float64), minlength=n)
        new_seeds = []
        new_groups = []
        for i in range(n):
            if cnt[i] == 0:
                continue
            cx, cy = int(sx[i] / cnt[i]), int(sy[i] / cnt[i])
            cand = cy * W + cx
            if group[cand] == label_group_list[i] and labels_init[cand] == -1:
                new_seeds.append(cand)
            else:
                new_seeds.append(seeds[i])
            new_groups.append(label_group_list[i])
        labels = labels_init.copy()
        label_group_list, seeds = new_groups, new_seeds
        fill_regions(grower, labels, group, label_group_list, seeds)
    return labels, label_group_list


def pair_counts(img2d, W):
    """Devuelve pares (a,b) a<b adyacentes y la longitud de frontera compartida."""
    a1 = img2d[:, :-1].ravel(); b1 = img2d[:, 1:].ravel()
    a2 = img2d[:-1, :].ravel(); b2 = img2d[1:, :].ravel()
    a3 = img2d[:, -1]; b3 = img2d[:, 0]
    a = np.concatenate([a1, a2, a3]); b = np.concatenate([b1, b2, b3])
    m = (a != b) & (a >= 0) & (b >= 0)
    a, b = a[m], b[m]
    lo = np.minimum(a, b).astype(np.int64); hi = np.maximum(a, b).astype(np.int64)
    key = lo * 1_000_000 + hi
    uk, cnt = np.unique(key, return_counts=True)
    return uk // 1_000_000, uk % 1_000_000, cnt


def merge_tiny(labels, label_group, W, min_px, same_group_only=True):
    """Fusiona etiquetas diminutas con la vecina de mismo grupo con más frontera."""
    n = len(label_group)
    lg = np.array(label_group)
    for _ in range(4):
        idx = labels >= 0
        cnt = np.bincount(labels[idx], minlength=n)
        tiny = set(np.nonzero((cnt > 0) & (cnt < min_px))[0].tolist())
        if not tiny:
            break
        a, b, c = pair_counts(labels.reshape(-1, W), W)
        best = {}
        for x, y, k in zip(a.tolist(), b.tolist(), c.tolist()):
            for s, t in ((x, y), (y, x)):
                if s in tiny and (not same_group_only or lg[s] == lg[t]) and cnt[t] >= cnt[s]:
                    if k > best.get(s, (0, -1))[0]:
                        best[s] = (k, t)
        if not best:
            break
        remap = np.arange(n)
        for s, (_, t) in best.items():
            remap[s] = t
        for _ in range(8):  # resolver cadenas
            remap = remap[remap]
        labels[idx] = remap[labels[idx]]
    return labels



def merge_islands(labels, label_group, W, wmap, T, frac=0.3):
    """Fusiona etiquetas muy pequeñas (islotes) con la etiqueta más cercana de su grupo."""
    n = len(label_group)
    lg = np.array(label_group)
    idx = np.nonzero(labels >= 0)[0]
    lab = labels[idx]
    cnt = np.bincount(lab, minlength=n).astype(np.float64)
    ws = np.bincount(lab, weights=wmap[idx], minlength=n)
    sx = np.bincount(lab, weights=(idx % W).astype(np.float64), minlength=n)
    sy = np.bincount(lab, weights=(idx // W).astype(np.float64), minlength=n)
    cx = sx / np.maximum(cnt, 1); cy = sy / np.maximum(cnt, 1)
    expected = T / np.maximum(ws / np.maximum(cnt, 1), 1e-3)
    remap = np.arange(n)
    by_group = {}
    for i in np.nonzero(cnt > 0)[0].tolist():
        by_group.setdefault(int(lg[i]), []).append(i)
    merged = 0
    for g, labs in by_group.items():
        if len(labs) < 2:
            continue
        labs_arr = np.array(labs)
        for i in labs:
            if cnt[i] >= frac * expected[i]:
                continue
            cand = labs_arr[(cnt[labs_arr] > cnt[i])]
            if cand.size == 0:
                continue
            d = (cx[cand] - cx[i]) ** 2 + (cy[cand] - cy[i]) ** 2
            remap[i] = int(cand[int(np.argmin(d))])
            merged += 1
    for _ in range(10):
        remap = remap[remap]
    labels[idx] = remap[lab]
    return labels, merged

def bfs_distance(grower, sources_mask, passable_mask, cap=255):
    """Distancia en pasos (4-vecindad, con wrap) desde sources por píxeles passable."""
    dist = np.full(sources_mask.size, cap, dtype=np.int32)
    frontier = np.nonzero(sources_mask)[0]
    dist[frontier] = 0
    d = 0
    while frontier.size and d < cap - 1:
        d += 1
        nb = grower.neighbors(frontier).ravel()
        nb = nb[nb >= 0]
        nb = nb[(dist[nb] == cap) & passable_mask[nb]]
        nb = np.unique(nb)
        dist[nb] = d
        frontier = nb
    return dist


# --------------------------------------------------------------- principal
def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true")
    args = ap.parse_args()

    rules = json.load(open(os.path.join(HERE, "world_rules.json"), encoding="utf-8"))
    cultures = json.load(open(os.path.join(DATA, "cultures", "cultures.json"), encoding="utf-8"))
    culture_religion = {c["id"]: c["religion"] for c in cultures["cultures"]}
    cfg = rules["map"]
    rng = np.random.default_rng(cfg["seed"])
    proj = Projection(cfg["width"], cfg["lat_top"], cfg["lat_bottom"])
    W, H = proj.W, proj.H
    N = W * H
    log(f"mapa {W}x{H} ({N/1e6:.1f} Mpx)")
    grower = Grower(W, H, rng)

    # --- admin-1 → raster
    admin1 = load_geojson("admin1", args.offline)
    skip = set(rules["skip_adm0"])
    feats = [f for f in admin1["features"] if f["properties"]["adm0_a3"] not in skip]
    for i, f in enumerate(feats):
        f["_id"] = i + 1
    log(f"rasterizando {len(feats)} unidades admin-1")
    A = raster_features(proj, feats, lambda f: f["_id"],
                        order_key=lambda f: f["properties"].get("area_sqkm") or 0).ravel()
    land = A > 0
    log(f"tierra: {land.sum()/N*100:.1f}%")
    a_props = [None] + [f["properties"] for f in feats]
    n_a = len(a_props)

    # --- latitud/longitud por píxel (vectores por fila/columna)
    rows_lat = proj.lat_of_row(np.arange(H))
    cols_lon = proj.lon_of_col(np.arange(W))
    pix_lat = np.repeat(rows_lat, W)
    pix_lon = np.tile(cols_lon, H)
    # área aproximada por píxel (km²)
    dx_km = 40075.0 * np.cos(np.radians(rows_lat)) / W
    dphi = (proj.y_top - proj.y_bot) / H * np.cos(0.8 * np.radians(rows_lat))
    dy_km = dphi * 6371.0
    pix_km2 = np.repeat(dx_km * dy_km, W)

    def box_field(entries, key, default):
        out = np.full(N, float(default))
        done = np.zeros(N, dtype=bool)
        for e in entries:
            b = e["box"]
            m = (~done) & (pix_lon >= b[0]) & (pix_lon <= b[2]) & (pix_lat >= b[1]) & (pix_lat <= b[3])
            out[m] = e[key]
            done |= m
        return out

    wmap = box_field(rules["province_density"], "w", rules["default_province_density"])
    dens = box_field(rules["population_density"], "d", rules["default_population_density"])

    # --- fusionar unidades admin-1 diminutas en "regiones de estado"
    wa = np.bincount(A[land], weights=wmap[land], minlength=n_a)
    T = wa.sum() / cfg["target_land_provinces"]
    log(f"área ponderada objetivo por provincia: {T:.1f}")
    a_adm0 = [p["adm0_a3"] if p else "" for p in a_props]
    pa, pb, pc = pair_counts(A.reshape(H, W) - 1, W)
    pa += 1; pb += 1
    adj = {}
    for x, y, k in zip(pa.tolist(), pb.tolist(), pc.tolist()):
        if x == 0 or y == 0 or a_adm0[x] != a_adm0[y]:
            continue
        adj.setdefault(x, {})[y] = k
        adj.setdefault(y, {})[x] = k
    parent = list(range(n_a))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    size = {i: wa[i] for i in range(1, n_a) if wa[i] > 0}
    min_state = 1.8 * T
    changed = True
    while changed:
        changed = False
        for i in sorted(size, key=lambda k: size[k]):
            r = find(i)
            if r != i or size[r] >= min_state:
                continue
            members = [j for j in range(1, n_a) if find(j) == r] if False else None
            best, best_sz = None, None
            for nb_ in adj.get(r, {}):
                t = find(nb_)
                if t == r:
                    continue
                if best is None or size[t] < best_sz:
                    best, best_sz = t, size[t]
            if best is not None:
                parent[r] = best
                size[best] += size[r]
                # unir adyacencias
                for nb_, k in adj.get(r, {}).items():
                    adj.setdefault(best, {})[nb_] = adj.get(best, {}).get(nb_, 0) + k
                del size[r]
                changed = True
    roots = sorted({find(i) for i in range(1, n_a) if wa[i] > 0})
    region_of_root = {r: k for k, r in enumerate(roots)}
    a_region = np.full(n_a, -1, dtype=np.int64)
    for i in range(1, n_a):
        if wa[i] > 0:
            a_region[i] = region_of_root[find(i)]
    R = np.where(land, a_region[A], -2)
    n_regions = len(roots)
    region_members = [[] for _ in range(n_regions)]
    for i in range(1, n_a):
        if a_region[i] >= 0:
            region_members[a_region[i]].append(i)
    log(f"{n_regions} regiones de estado tras fusionar admin-1 pequeñas")

    # --- provincias terrestres
    land_idx = np.nonzero(land)[0]
    order = np.argsort(R[land_idx], kind="stable")
    sorted_idx = land_idx[order]
    counts = np.bincount(R[land_idx], minlength=n_regions)
    starts = np.concatenate([[0], np.cumsum(counts)])
    reg_wa = np.bincount(R[land_idx], weights=wmap[land_idx], minlength=n_regions)
    seeds, seed_groups = [], []
    for r in range(n_regions):
        pix = sorted_idx[starts[r]:starts[r + 1]]
        if pix.size == 0:
            continue
        k = max(1, int(round(reg_wa[r] / T)))
        k = min(k, max(1, pix.size // 30))
        w = wmap[pix]
        chosen = rng.choice(pix, size=k, replace=False, p=w / w.sum())
        seeds.extend(chosen.tolist())
        seed_groups.extend([r] * k)
    log(f"{len(seeds)} semillas de provincia; creciendo regiones...")
    labels0 = np.where(land, -1, -2).astype(np.int64)
    group = R.astype(np.int64)
    P, p_group = relax(grower, labels0, group, seed_groups, seeds, iterations=2)
    P = merge_tiny(P, p_group, W, min_px=10)
    P, nm = merge_islands(P, p_group, W, wmap, T)
    log(f"{nm} islotes fusionados con su provincia más cercana")
    # renumerar provincias 1..n
    used = np.unique(P[P >= 0])
    remap = np.full(len(p_group), -1, dtype=np.int64)
    remap[used] = np.arange(1, used.size + 1)
    P = np.where(P >= 0, remap[np.clip(P, 0, None)], 0)
    p_region = np.zeros(used.size + 1, dtype=np.int64)
    p_region[1:] = np.array(p_group)[used]
    n_land = used.size
    log(f"{n_land} provincias terrestres")

    # --- zonas marítimas (primera pasada: detectar agua diminuta)
    water = ~land
    dist_land = bfs_distance(grower, land, water)
    sw = np.where(dist_land <= 18, 1.0, np.where(dist_land <= 60, 0.22, 0.035))
    water_idx = np.nonzero(water)[0]
    k_sea = int(cfg["target_sea_zones"])
    sea_seeds = rng.choice(water_idx, size=k_sea, replace=False, p=sw[water_idx] / sw[water_idx].sum()).tolist()
    labels0 = np.where(water, -1, -2).astype(np.int64)
    sgroup = np.where(water, 0, -1).astype(np.int64)
    log(f"{k_sea} semillas marítimas; creciendo...")
    S, s_group = relax(grower, labels0, sgroup, [0] * k_sea, sea_seeds, iterations=2)
    S = merge_tiny(S, s_group, W, min_px=40, same_group_only=False)

    def water_components(S):
        used_s = np.unique(S[S >= 0])
        s_area = np.bincount(S[S >= 0], minlength=len(s_group))
        sa, sb, _ = pair_counts(S.reshape(H, W), W)
        water_nb = {}
        for x, y in zip(sa.tolist(), sb.tolist()):
            water_nb.setdefault(x, set()).add(y)
            water_nb.setdefault(y, set()).add(x)
        comp_total = {}
        seen_c = set()
        for s0 in used_s.tolist():
            if s0 in seen_c:
                continue
            stack, members = [s0], []
            seen_c.add(s0)
            while stack:
                u = stack.pop(); members.append(u)
                for v in water_nb.get(u, ()):
                    if v not in seen_c:
                        seen_c.add(v); stack.append(v)
            tot = int(sum(int(s_area[m]) for m in members))
            for m in members:
                comp_total[m] = tot
        return used_s, comp_total

    used_s, comp_total = water_components(S)
    tiny_lab = np.array([s0 for s0 in used_s.tolist() if comp_total[s0] < 150], dtype=np.int64)
    flip = (S >= 0) & np.isin(S, tiny_lab)
    log(f"{flip.sum()} píxeles de agua diminuta convertidos en tierra")
    # rellenar con la provincia terrestre vecina
    lab_fill = np.where(P > 0, P, -2).astype(np.int64)
    lab_fill[flip] = -1
    grp = np.where(flip | (P > 0), 0, -1).astype(np.int64)
    lgrp = np.zeros(int(P.max()) + 2, dtype=np.int64); lgrp[-1] = -9
    grower.grow(lab_fill, grp, lgrp, p=1.0, seeds=np.nonzero(P > 0)[0])
    P = np.where(flip & (lab_fill > 0), lab_fill, P)
    land = P > 0
    S = np.where(land, -2, S)
    water = ~land
    used_s, comp_total = water_components(S)
    s_area = np.bincount(S[S >= 0], minlength=len(s_group))

    # --- distancias a costa
    dist_sea = bfs_distance(grower, water, land)   # para tierra: distancia al agua
    dist_land = bfs_distance(grower, land, water)  # para agua: distancia a tierra

    seas = [s0 for s0 in used_s.tolist() if comp_total[s0] >= 2500]
    lakes = [s0 for s0 in used_s.tolist() if comp_total[s0] < 2500]
    ids = np.zeros(len(s_group), dtype=np.int64)
    for i, s0 in enumerate(seas):
        ids[s0] = n_land + 1 + i
    for i, s0 in enumerate(lakes):
        ids[s0] = n_land + 1 + len(seas) + i
    ID = np.where(land, P, ids[np.clip(S, 0, None)])
    n_sea, n_lake = len(seas), len(lakes)
    n_total = n_land + n_sea + n_lake
    log(f"{n_sea} zonas marítimas, {n_lake} lagos; total ids {n_total}")
    assert n_total < 65536

    # --- terreno por píxel
    geo = load_geojson("regions", args.offline)
    gmap = rules["geography_terrain"]
    G = raster_features(proj, geo["features"],
                        lambda f: T_INDEX.get(gmap.get(f["properties"].get("FEATURECLA"), ""), None),
                        mode="I").ravel()
    base_t = np.zeros(N, dtype=np.int32)
    done = np.zeros(N, dtype=bool)
    for e in rules["climate_terrain"]:
        m = ~done
        if "box" in e:
            b = e["box"]
            m &= (pix_lon >= b[0]) & (pix_lon <= b[2]) & (pix_lat >= b[1]) & (pix_lat <= b[3])
        if "lat_min" in e:
            m &= pix_lat >= e["lat_min"]
        if "lat_max" in e:
            m &= pix_lat <= e["lat_max"]
        base_t[m] = T_INDEX[e["terrain"]]
        done |= m
    strong = {T_INDEX["arctic"], T_INDEX["desert"], T_INDEX["jungle"]}
    over = (G > 0) & ~np.isin(base_t, list(strong) if False else [T_INDEX["arctic"]])
    # el relieve (montaña) gana siempre salvo en el ártico; desierto/pantano sobre templado
    pt = np.where(over, G, base_t)
    lp = ID[land]
    tcount = np.bincount(lp * 16 + pt[land], minlength=(n_land + 1) * 16).reshape(n_land + 1, 16)

    # --- agregados por provincia
    all_ids = ID
    cnt = np.bincount(all_ids, minlength=n_total + 1)
    xs = (np.arange(N) % W).astype(np.float64)
    ys = (np.arange(N) // W).astype(np.float64)
    sx = np.bincount(all_ids, weights=xs, minlength=n_total + 1)
    sy = np.bincount(all_ids, weights=ys, minlength=n_total + 1)
    km2 = np.bincount(all_ids, weights=pix_km2, minlength=n_total + 1)
    popw = np.bincount(all_ids, weights=pix_km2 * dens, minlength=n_total + 1)
    wsum = np.bincount(all_ids, weights=wmap, minlength=n_total + 1)
    # bbox
    minx = np.full(n_total + 1, W); maxx = np.zeros(n_total + 1, dtype=np.int64)
    miny = np.full(n_total + 1, H); maxy = np.zeros(n_total + 1, dtype=np.int64)
    np.minimum.at(minx, all_ids, (np.arange(N) % W)); np.maximum.at(maxx, all_ids, (np.arange(N) % W))
    np.minimum.at(miny, all_ids, (np.arange(N) // W)); np.maximum.at(maxy, all_ids, (np.arange(N) // W))
    # centroide robusto: si el centroide cae fuera de la provincia, usar el píxel más cercano propio
    cx = sx / np.maximum(cnt, 1); cy = sy / np.maximum(cnt, 1)
    # provincias que cruzan el antimeridiano: bbox enorme → usar mitad mayor
    log("calculando vecindades")
    a, b, c = pair_counts(ID.reshape(H, W), W)
    neighbors = {i: set() for i in range(1, n_total + 1)}
    for x, y in zip(a.tolist(), b.tolist()):
        if x > 0 and y > 0:
            neighbors[x].add(y); neighbors[y].add(x)
    kind = {}
    for i in range(1, n_total + 1):
        kind[i] = LAND if i <= n_land else (SEA if i <= n_land + n_sea else LAKE)

    def snap_inside(i):
        x, y = int(cx[i]), int(cy[i])
        if 0 <= x < W and 0 <= y < H and ID[y * W + x] == i:
            return x, y
        # buscar un píxel propio cercano al centroide
        x0, x1, y0, y1 = int(minx[i]), int(maxx[i]), int(miny[i]), int(maxy[i])
        sub = ID.reshape(H, W)[y0:y1 + 1, x0:x1 + 1]
        yy, xx = np.nonzero(sub == i)
        if xx.size == 0:
            return x, y
        d = (xx + x0 - cx[i]) ** 2 + (yy + y0 - cy[i]) ** 2
        j = int(np.argmin(d))
        return int(xx[j] + x0), int(yy[j] + y0)

    centers = {}
    for i in range(1, n_total + 1):
        if maxx[i] - minx[i] > W / 2:  # cruza el borde: usar el lado con más píxeles
            centers[i] = (int(cx[i]), int(cy[i]))
        else:
            centers[i] = snap_inside(i)

    def lonlat(i):
        x, y = centers[i]
        return float(proj.lon_of_col(x)), float(proj.lat_of_row(y))

    # --- nombres: ciudades
    places = load_geojson("places", args.offline)["features"]
    by_prov = {}
    plist = []
    for f in places:
        pr = f["properties"]
        lon, lat = f["geometry"]["coordinates"][:2]
        x, y = proj.xy(lon, lat)
        xi, yi = int(x), int(y)
        if not (0 <= xi < W and 0 <= yi < H):
            continue
        pid = int(ID[yi * W + xi])
        pop = pr.get("pop_max") or 0
        name = pr.get("name") or pr.get("nameascii")
        plist.append((pop, name, pid, xi, yi))
        if pid and kind[pid] == LAND:
            by_prov.setdefault(pid, []).append((pop, name))
    used_names = set()
    city_pop = np.zeros(n_total + 1)

    # nombres en español de admin-1
    def a_name(ai):
        p = a_props[ai]
        return (p.get("name_es") or p.get("name") or p.get("name_en") or "Sin nombre").strip()

    # --- datos por región: país moderno, nombre
    region_adm0 = [a_adm0[m[0]] if m else "" for m in region_members]

    def region_name(r):
        mem = region_members[r]
        if not mem:
            return f"Región {r}"
        if len(mem) > 1:
            regs = {(a_props[m].get("region") or "").strip() for m in mem}
            if len(regs) == 1 and next(iter(regs)) and len(next(iter(regs))) < 32:
                return next(iter(regs))
        big = max(mem, key=lambda m: wa[m])
        return a_name(big)

    # --- asignación de propietario / cultura
    def assign(adm0, lon, lat):
        for rule in rules["assignments"]:
            if "adm0" in rule and adm0 not in rule["adm0"]:
                continue
            if "box" in rule and not in_box(rule["box"], lon, lat):
                continue
            if "lat_min" in rule and lat < rule["lat_min"]:
                continue
            if "lat_max" in rule and lat > rule["lat_max"]:
                continue
            if "lon_min" in rule and lon < rule["lon_min"]:
                continue
            if "lon_max" in rule and lon > rule["lon_max"]:
                continue
            return rule["owner"], rule["culture"], rule.get("religion")
        return "", "bantu", None

    log("asignando terreno, RGO, población, propietarios")
    provinces_out = []
    p_terrain = {}
    temperate_w = rules["temperate_terrain_weights"]
    for i in range(1, n_land + 1):
        lon, lat = lonlat(i)
        tc = tcount[i].copy()
        # el terreno 0 (templado) se resuelve con pesos por provincia
        if tc[0] >= tc[1:].max():
            tw = dict(temperate_w)
            avg_w = wsum[i] / max(cnt[i], 1)
            if avg_w >= 2.0:
                tw["farmlands"] = tw.get("farmlands", 0) * 1.6
            terrain = weighted_pick(tw, "terrain", i)
        else:
            terrain = TERRAINS[int(np.argmax(tc[1:]))]
        p_terrain[i] = terrain
    # ciudades
    for i in range(1, n_land + 1):
        cand = sorted(by_prov.get(i, []), key=lambda t: -t[0])
        for pop, name in cand:
            city_pop[i] += pop
    for i in range(1, n_land + 1):
        lon, lat = lonlat(i)
        adm0 = region_adm0[p_region[i]]
        owner, culture, religion = assign(adm0, lon, lat)
        terrain = p_terrain[i]
        climate = "tropical" if abs(lat) < 23.5 else ("cold" if abs(lat) > 52 else "temperate")
        table = rules["rgo_tables"][terrain][climate]
        for ov in rules["rgo_overrides"]:
            if in_box(ov["box"], lon, lat) and terrain in ("farmlands", "plains", "hills", "woods"):
                table = ov["goods"]
                break
        coastal = any(kind[n] == SEA for n in neighbors[i])
        if coastal and stable_rand("fish", i) < 0.12 and terrain not in ("mountains",):
            rgo = "fish"
        else:
            rgo = weighted_pick(table, "rgo", i)
        tmult = rules["terrain_population_multiplier"][terrain]
        noise = 0.65 + 0.7 * stable_rand("pop", i)
        pop = popw[i] * tmult * noise + (city_pop[i] ** 0.62) * 9.0
        pop = int(max(500, pop) // 10 * 10)
        life = {"farmlands": 33, "plains": 30, "woods": 27, "forest": 22, "hills": 25, "mountains": 18,
                "steppe": 20, "desert": 12, "jungle": 16, "marsh": 18, "tundra": 10, "arctic": 6}[terrain]
        life = int(life + stable_rand("life", i) * 8 - 3)
        avg_w = wsum[i] / max(cnt[i], 1)
        provinces_out.append({
            "id": i,
            "owner": owner,
            "culture": culture,
            "religion": religion or culture_religion.get(culture, "animista"),
            "terrain": terrain,
            "rgo": rgo,
            "life_rating": life,
            "population": pop,
            "infrastructure": 1 if avg_w >= 1.6 else 0,
            "_lon": round(lon, 3), "_lat": round(lat, 3),
            "_region": int(p_region[i]),
            "_coastal": coastal,
        })

    # nombres de provincia: ciudad principal propia; si no, ciudad libre cercana; si no, región + ordinal
    plist.sort(key=lambda t: -t[0])
    for po in provinces_out:
        i = po["id"]
        name = None
        for pop, nm in sorted(by_prov.get(i, []), key=lambda t: -t[0]):
            if nm and nm not in used_names:
                name = nm
                break
        po["name"] = name
        if name:
            used_names.add(name)
    unnamed = [po for po in provinces_out if not po["name"]]
    if unnamed:
        free = [(x, y, nm) for pop, nm, pid, x, y in plist if nm and nm not in used_names]
        fx = np.array([f[0] for f in free], dtype=np.float64) if free else np.zeros(0)
        fy = np.array([f[1] for f in free], dtype=np.float64) if free else np.zeros(0)
        taken = np.zeros(len(free), dtype=bool)
        for po in unnamed:
            x, y = centers[po["id"]]
            if fx.size:
                d = (fx - x) ** 2 + (fy - y) ** 2
                d[taken] = 1e18
                j = int(np.argmin(d))
                if d[j] < 26 ** 2:
                    po["name"] = free[j][2]
                    taken[j] = True
                    used_names.add(free[j][2])
    # --- estados: dividir regiones grandes
    states_out = []
    prov_by_region = {}
    for po in provinces_out:
        prov_by_region.setdefault(po["_region"], []).append(po["id"])
    max_per = cfg["max_provinces_per_state"]
    sid = 0
    state_of = {}
    for r, plist_r in sorted(prov_by_region.items()):
        base_name = region_name(r)
        n = len(plist_r)
        k = max(1, int(math.ceil(n / max_per)))
        if k == 1:
            parts = [plist_r]
        else:
            # semillas por muestreo del punto más lejano
            pts = {p: centers[p] for p in plist_r}
            seeds_s = [max(plist_r, key=lambda p: pts[p][0] + pts[p][1])]
            while len(seeds_s) < k:
                far = max(plist_r, key=lambda p: min((pts[p][0] - pts[s][0]) ** 2 + (pts[p][1] - pts[s][1]) ** 2 for s in seeds_s))
                seeds_s.append(far)
            owner_part = {s: j for j, s in enumerate(seeds_s)}
            queue = list(seeds_s)
            target = n / k
            sizes = [1] * k
            # BFS por adyacencia (multi-fuente, equilibrando tamaños)
            setr = set(plist_r)
            progress = True
            while progress:
                progress = False
                for j in sorted(range(k), key=lambda q: sizes[q]):
                    frontier = [p for p, o in owner_part.items() if o == j]
                    for p in frontier:
                        for nb_ in sorted(neighbors[p]):
                            if nb_ in setr and nb_ not in owner_part:
                                owner_part[nb_] = j
                                sizes[j] += 1
                                progress = True
                                break
                        if progress:
                            break
            for p in plist_r:  # islas sin conexión: a la parte más cercana
                if p not in owner_part:
                    owner_part[p] = min(range(k), key=lambda j: (pts[p][0] - pts[seeds_s[j]][0]) ** 2 + (pts[p][1] - pts[seeds_s[j]][1]) ** 2)
            parts = [[p for p in plist_r if owner_part[p] == j] for j in range(k)]
            parts = [pp for pp in parts if pp]
        rcx = sum(centers[p][0] for p in plist_r) / n
        rcy = sum(centers[p][1] for p in plist_r) / n
        for pp in parts:
            sid += 1
            if len(parts) > 1:
                pcx = sum(centers[p][0] for p in pp) / len(pp)
                pcy = sum(centers[p][1] for p in pp) / len(pp)
                dx, dy = pcx - rcx, pcy - rcy
                if abs(dx) < 4 and abs(dy) < 4:
                    suffix = "central"
                elif abs(dx) > abs(dy):
                    suffix = "oriental" if dx > 0 else "occidental"
                else:
                    suffix = "meridional" if dy > 0 else "septentrional"
                name = f"{base_name} {suffix}"
            else:
                name = base_name
            states_out.append({"id": sid, "name": name, "provinces": pp, "modern_region": region_adm0[r]})
            for p in pp:
                state_of[p] = sid
    # nombres repetidos de estado → numeral
    seen = {}
    for st in states_out:
        seen.setdefault(st["name"], []).append(st)
    for name, lst in seen.items():
        if len(lst) > 1:
            for j, st in enumerate(lst):
                st["name"] = f"{name} {ROMAN[min(j + 1, 20)]}"
    st_by_id = {s["id"]: s for s in states_out}
    # provincias sin nombre: estado + ordinal
    for po in provinces_out:
        po["state"] = state_of[po["id"]]
        if not po["name"]:
            st = st_by_id[po["state"]]
            k = st["provinces"].index(po["id"]) + 1
            po["name"] = f"{st['name']} {ROMAN[min(k, 20)]}" if len(st["provinces"]) > 1 else st["name"]
    # nombres repetidos de provincia → sufijo
    seen = {}
    for po in provinces_out:
        seen.setdefault(po["name"], []).append(po)
    for name, lst in seen.items():
        if len(lst) > 1:
            for j, po in enumerate(lst[1:], start=2):
                po["name"] = f"{name} {ROMAN[min(j, 20)]}"

    # --- nombres de zonas marítimas
    marine = load_geojson("marine", args.offline)["features"]
    mnames = [None] + [((f["properties"].get("name_es") or f["properties"].get("name") or "Mar").title()) for f in marine]
    for i, f in enumerate(marine):
        f["_id"] = i + 1
    def marine_area(f):
        tot = 0.0
        for poly in rings_of(f.get("geometry")):
            ring = poly[0]
            s = 0.0
            for (x0, y0), (x1, y1) in zip(ring, ring[1:]):
                s += x0 * y1 - x1 * y0
            tot += abs(s) / 2
        return tot
    M = raster_features(proj, marine, lambda f: f["_id"], order_key=marine_area).ravel()
    wpix = np.nonzero(water)[0]
    mc = np.bincount(ID[wpix].astype(np.int64) * (len(mnames)) + M[wpix], minlength=(n_total + 1) * len(mnames)).reshape(n_total + 1, len(mnames))
    sea_out = []
    used_sea = {}
    for i in range(n_land + 1, n_total + 1):
        row = mc[i].copy()
        row[0] = 0
        j = int(np.argmax(row))
        if row[j] == 0:
            lon, lat = lonlat(i)
            base = "Lago" if kind[i] == LAKE else ("Océano" if abs(lat) < 60 else "Mar Polar")
        else:
            base = mnames[j]
        used_sea.setdefault(base, 0)
        used_sea[base] += 1
        sea_out.append({"id": i, "kind": kind[i], "base": base})
    count_base = {}
    for s in sea_out:
        count_base[s["base"]] = count_base.get(s["base"], 0) + 1
    seen_b = {}
    for s in sea_out:
        b_ = s.pop("base")
        if count_base[b_] > 1:
            seen_b[b_] = seen_b.get(b_, 0) + 1
            s["name"] = f"{b_} {ROMAN[min(seen_b[b_], 20)]}" if seen_b[b_] <= 20 else f"{b_} {seen_b[b_]}"
        else:
            s["name"] = b_

    # --- adyacencias explícitas (estrechos / pasos)
    def nearest_of_kind(lon, lat, want):
        x, y = proj.xy(lon, lat)
        x, y = int(x), int(y)
        for rad in range(0, 40):
            x0, x1 = max(0, x - rad), min(W - 1, x + rad)
            y0, y1 = max(0, y - rad), min(H - 1, y + rad)
            sub = ID.reshape(H, W)[y0:y1 + 1, x0:x1 + 1]
            for v in np.unique(sub):
                if v and kind[int(v)] == want:
                    return int(v)
        return 0
    adjacencies = []
    for s in rules["straits"]:
        a_ = nearest_of_kind(*s["a"], SEA); b_ = nearest_of_kind(*s["b"], SEA)
        if a_ and b_ and a_ != b_ and b_ not in neighbors[a_]:
            adjacencies.append({"a": a_, "b": b_, "type": "sea_strait", "name": s["name"]})
    for s in rules["land_crossings"]:
        a_ = nearest_of_kind(*s["a"], LAND); b_ = nearest_of_kind(*s["b"], LAND)
        if a_ and b_ and a_ != b_ and b_ not in neighbors[a_]:
            adjacencies.append({"a": a_, "b": b_, "type": "land_crossing", "name": s["name"]})

    # --- escribir salidas
    os.makedirs(os.path.join(DATA, "map"), exist_ok=True)
    os.makedirs(os.path.join(DATA, "provinces"), exist_ok=True)
    os.makedirs(os.path.join(DATA, "states"), exist_ok=True)
    dist = np.where(land, dist_sea, dist_land).clip(0, 255).astype(np.uint8)
    rgb = np.zeros((N, 3), dtype=np.uint8)
    rgb[:, 0] = (ID & 0xFF).astype(np.uint8)
    rgb[:, 1] = ((ID >> 8) & 0xFF).astype(np.uint8)
    rgb[:, 2] = dist
    Image.fromarray(rgb.reshape(H, W, 3), "RGB").save(os.path.join(DATA, "map", "provinces.png"), optimize=True)
    geometry = []
    for i in range(1, n_total + 1):
        lon, lat = lonlat(i)
        geometry.append({
            "id": i, "kind": kind[i],
            "center": list(centers[i]),
            "bbox": [int(minx[i]), int(miny[i]), int(maxx[i]), int(maxy[i])],
            "area_px": int(cnt[i]), "area_km2": int(km2[i]),
            "lonlat": [round(lon, 2), round(lat, 2)],
            "neighbors": sorted(neighbors[i]),
        })
    meta = {
        "width": W, "height": H,
        "projection": {"type": "miller", "lat_top": cfg["lat_top"], "lat_bottom": cfg["lat_bottom"]},
        "id_encoding": "id = R + G*256 ; B = distancia a la costa en píxeles (0..255)",
        "land_count": n_land, "sea_count": n_sea, "lake_count": n_lake,
        "first_sea_id": n_land + 1, "first_lake_id": n_land + n_sea + 1,
        "wrap_x": True,
        "source": "Natural Earth (dominio público): " + ", ".join(SOURCES.values()),
        "generator": "tools/map_import/build_world.py",
    }
    def dump(path, obj, compact=False):
        with open(os.path.join(DATA, path), "w", encoding="utf-8") as fh:
            if compact:
                fh.write("[\n" + ",\n".join(json.dumps(o, ensure_ascii=False, separators=(",", ":")) for o in obj) + "\n]\n")
            else:
                json.dump(obj, fh, ensure_ascii=False, indent=1)
    dump("map/map.json", meta)
    dump("map/geometry.json", geometry, compact=True)
    dump("map/adjacencies.json", adjacencies)
    for po in provinces_out:
        for k in [k for k in po if k.startswith("_")]:
            po.pop(k)
    order_keys = ["id", "name", "state", "owner", "culture", "religion", "terrain", "rgo", "life_rating", "population", "infrastructure"]
    provinces_out = [{k: po[k] for k in order_keys} for po in provinces_out]
    dump("provinces/provinces.json", provinces_out, compact=True)
    dump("provinces/sea_zones.json", sea_out, compact=True)
    dump("states/states.json", states_out, compact=True)
    owners = {}
    for po in provinces_out:
        owners[po["owner"]] = owners.get(po["owner"], 0) + 1
    log(f"estados: {len(states_out)}; provincias por propietario (top): {sorted(owners.items(), key=lambda t: -t[1])[:12]}")
    log(f"población total: {sum(po['population'] for po in provinces_out)/1e6:.0f} M")
    log("hecho")


if __name__ == "__main__":
    main()
