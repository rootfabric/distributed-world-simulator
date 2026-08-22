"""Tests for ECO.EVO5/A0 factor registry. Run directly: python test_evo5_factor_registry.py"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts/research/ecology"))
from evo5_factor_registry_v1 import (  # noqa: E402
    PPM_MAX,
    compute_site_context,
    register_factor,
)

BASE = {
    "light_availability_ppm": 550000,
    "soil_moisture_ppm": 400000,
    "nutrient_availability_ppm": 500000,
    "disturbance_pressure_ppm": 50000,
    "temperature_milli_c": 15000,
}


def _eq(label: str, ok: bool) -> None:
    if not ok:
        raise SystemExit(f"FAIL {label}")
    print(f"ok {label}")


def main() -> int:
    ctx_a = compute_site_context(BASE, {"cavity_depth_m": 2.0, "water_dist_m": 3.0, "rock_count": 2})
    ctx_b = compute_site_context(BASE, {"rock_count": 2, "water_dist_m": 3.0, "cavity_depth_m": 2.0})
    _eq("determinism+order-independence", ctx_a == ctx_b)
    _eq("applied sorted canonically", [f["factor_id"] for f in ctx_a["applied_factors"]] == sorted(f["factor_id"] for f in ctx_a["applied_factors"]))
    eff = ctx_a["effective_conditions"]
    _eq("clamped within bounds", all(0 <= v <= PPM_MAX for k, v in eff.items() if k.endswith("_ppm")))
    _eq("cavity darkened light", eff["light_availability_ppm"] < BASE["light_availability_ppm"])
    _eq("water raised soil moisture", eff["soil_moisture_ppm"] > BASE["soil_moisture_ppm"])
    _eq("mineral channel appears", "mineral_richness_ppm" in compute_site_context(BASE, {"mineral_deposit": {"type": "iron_vein", "richness": 0.9}})["effective_conditions"])
    register_factor("ash_fall", ["ash_depth_cm"], lambda f: ({"light_availability_ppm": -120000} if float(f.get("ash_depth_cm", 0.0)) > 0.5 else {}))
    ash_ctx = compute_site_context(BASE, {"ash_depth_cm": 1.0})
    _eq("data-only factor registration works", ash_ctx["effective_conditions"]["light_availability_ppm"] == 430000)
    plain_ctx = compute_site_context(BASE, {})
    _eq("no features -> no factors", plain_ctx["applied_factors"] == [] and plain_ctx["effective_conditions"] == {k: int(v) for k, v in BASE.items()})
    try:
        register_factor("ash_fall", ["x"], lambda f: {})
        raise SystemExit("FAIL duplicate registration must reject")
    except ValueError:
        print("ok duplicate registration rejected fail-closed")
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
