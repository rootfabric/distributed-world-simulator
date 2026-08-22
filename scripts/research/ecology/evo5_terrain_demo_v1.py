"""ECO.EVO5 - terrain generator demo: relief -> factors -> evolution.

Deterministic 14x14 heightfield with declared landforms (ravine, hill, river,
ore vein, snow patch, slopes). Each cell derives site_features, gets effective
conditions via the A0 factor registry, is assigned to a zone, and runs a
20-generation gene micro-evolution under its zone's herbivory pressure
(pressure derived FROM conditions). Emits JSON artifacts + a PIL heatmap.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))
from evo5_factor_registry_v1 import compute_site_context  # noqa: E402

N = 14
BASE = {"light_availability_ppm": 550000, "soil_moisture_ppm": 400000,
        "nutrient_availability_ppm": 500000, "disturbance_pressure_ppm": 50000,
        "temperature_milli_c": 15000}
OUT_TERRAIN = ROOT / "validation/ecology/evo5_terrain_demo.v1.json"
OUT_EVO = ROOT / "validation/ecology/evo5_terrain_evolution.v1.json"


def _unit(s: str) -> float:
    return int(hashlib.sha256(s.encode()).hexdigest()[:12], 16) / float(2 ** 48)


def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


def build_heightfield() -> list[list[float]]:
    h = [[1.0 + 0.15 * _unit(f"base|{x}|{z}") for x in range(N)] for z in range(N)]
    for x in range(N):  # ravine along z=7..8
        for z in (7, 8):
            h[z][x] -= 2.2 * math.exp(-((z - 7.5) ** 2) / 1.2)
    for cx, cz, rad in [(4, 4, 2.6), (11, 10, 2.2)]:  # hills
        for z in range(N):
            for x in range(N):
                d = math.hypot(x - cx, z - cz)
                if d < rad:
                    h[z][x] += 2.0 * math.cos(d / rad * math.pi / 2) ** 2
    river_z = [5.0 + 2.5 * math.sin(x / 3.0) for x in range(N)]
    for x in range(N):
        h[int(round(river_z[x])) % N][x] -= 1.2  # riverbed carve
    for z in range(11, N):  # snow corner
        for x in range(0, 4):
            h[z][x] += 0.4
    h[9][11] += 0.9  # ore ridge bump
    h[9][12] += 0.7
    return h


def cell_features(h, x, z, river_z) -> dict:
    hh = [[h[zy][zx] for zx in range(N)] for zy in range(N)]
    def at(xx, zz):
        return h[_clamp(zz, 0, N - 1)][_clamp(xx, 0, N - 1)]
    slope = math.degrees(math.atan(max(abs(at(x+1,z)-at(x-1,z)), abs(at(x,z+1)-at(x,z-1))) / 2 / 0.5))
    neighbours = [at(xx, zz) for xx in range(x-1, x+2) for zz in range(z-1, z+2)]
    cavity = _clamp(sum(neighbours) / len(neighbours) - at(x, z), 0.0, 3.0)
    water_dist = min(abs(z - int(round(river_z[xe]))) + abs(x - xe) for xe in range(N))
    feats = {}
    if slope > 20:
        feats["slope_deg"] = round(slope, 1)
        feats["aspect_deg"] = 180.0 if at(x, z-1) < at(x, z) else 10.0
    if cavity > 1.0:
        feats["cavity_depth_m"] = round(cavity, 2)
    if z >= 11 and x < 4:
        feats["snow_cover_frac"] = 0.6
    if water_dist <= 2:
        feats["water_dist_m"] = float(water_dist)
    if (x, z) == (11, 9) or (x, z) == (12, 9):
        feats["mineral_deposit"] = {"type": "iron_vein", "richness": 0.9}
    if _unit(f"rock|x{x}z{z}") > 0.93:
        feats["rock_count"] = 2
    return feats


def zone_of(feats: dict) -> str:
    if feats.get("mineral_deposit"):
        return "iron_ridge"
    if feats.get("snow_cover_frac"):
        return "snow_corner"
    if feats.get("cavity_depth_m"):
        return "ravine_bottom"
    if feats.get("water_dist_m") is not None:
        return "riverside"
    if feats.get("slope_deg"):
        return "hill_slopes"
    return "plain"


def evolve_zone(zone: str, ctx: dict, gens: int = 20) -> dict:
    eff = ctx["effective_conditions"]
    pressure = _clamp(1.0 - eff["light_availability_ppm"] / 1e6 * 0.5 + eff["disturbance_pressure_ppm"] / 1e6 * 0.4, 0.15, 0.9)
    g = {"defense_intensity": 0.15, "toxicity": 0.1, "nutrient_value": 0.5}
    traj = []
    for gen in range(gens):
        vm = _clamp(1.0 - 0.30 * g["defense_intensity"] - 0.20 * g["toxicity"], 0.40, 1.15)
        fitness = vm - 0.85 * pressure * (1.0 - g["defense_intensity"]) - 0.05 * (g["toxicity"] > 0.6)
        grad = {"defense_intensity": (1.0 - g["defense_intensity"]) * pressure - 0.30 * g["defense_intensity"],
                "toxicity": 0.02 - 0.20 * g["toxicity"], "nutrient_value": 0.01}
        step = 0.08 * (1.0 if fitness > 0 else -1.0)
        for k in g:
            lo, hi = {"defense_intensity": (0.0, 0.95), "toxicity": (0.0, 0.9), "nutrient_value": (0.1, 1.0)}[k]
            g[k] = round(_clamp(g[k] + grad[k] * step, lo, hi), 4)
        traj.append(round(g["defense_intensity"], 3))
    return {"zone": zone, "pressure_used": round(pressure, 3),
            "conditions": {k: eff[k] for k in sorted(eff)},
            "final_genes": g, "defense_trajectory": traj}


def main() -> int:
    h = build_heightfield()
    river_z = [5.0 + 2.5 * math.sin(x / 3.0) for x in range(N)]
    cells = []
    for z in range(N):
        for x in range(N):
            feats = cell_features(h, x, z, river_z)
            ctx = compute_site_context(BASE, feats)
            cells.append({"x": x, "z": z, "height": round(h[z][x], 3),
                          "features": feats, "zone": zone_of(feats), "context": ctx})
    zones: dict[str, list] = {}
    for c in cells:
        zones.setdefault(c["zone"], []).append(c)
    evolution = {}
    for zone, zcells in sorted(zones.items()):
        evolution[zone] = evolve_zone(zone, zcells[0]["context"])
        evolution[zone]["cells"] = len(zcells)
    OUT_TERRAIN.write_text(json.dumps({"schema": "distributed_world_simulator.ecology.evo5_terrain_demo.v1",
        "size": N, "cells": cells}, ensure_ascii=False) + "\n", encoding="utf-8")
    OUT_EVO.write_text(json.dumps({"schema": "distributed_world_simulator.ecology.evo5_terrain_evolution.v1",
        "generations": 20, "zones": evolution}, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    try:
        from PIL import Image
        img = Image.new("RGB", (N * 16, N * 16))
        palette = {"plain": (110, 140, 80), "hill_slopes": (150, 130, 70), "ravine_bottom": (60, 90, 110),
                   "riverside": (70, 120, 160), "iron_ridge": (170, 100, 60), "snow_corner": (220, 220, 230)}
        for c in cells:
            col = palette[c["zone"]]
            shade = int(_clamp((c["height"] - 0.5) * 40, -35, 35))
            px = tuple(_clamp(v + shade, 0, 255) for v in col)
            for dy in range(16):
                for dx in range(16):
                    img.putpixel((c["x"] * 16 + dx, c["z"] * 16 + dy), px)
        img.save(str(ROOT / "artifacts/evo5_terrain_zones.png"))
        print("heatmap=artifacts/evo5_terrain_zones.png")
    except Exception as exc:  # noqa: BLE001 - heatmap optional
        print("heatmap skipped:", exc)
    diver = max(ev["pressure_used"] for ev in evolution.values()) - min(ev["pressure_used"] for ev in evolution.values())
    print(f"EVO5_TERRAIN_DEMO verdict=PASS sites={len(cells)} zones={len(zones)} pressure_divergence={round(diver,3)}")
    for zn, ev in sorted(evolution.items()):
        print(f"  {zn:>13}: P={ev['pressure_used']:<5} defense={ev['final_genes']['defense_intensity']} toxicity={ev['final_genes']['toxicity']} nutrient={ev['final_genes']['nutrient_value']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
