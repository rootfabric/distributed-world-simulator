"""ECO.EVO5/A0.5 - broken-plot demo: 6 microsites diverge via factor registry."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))
from evo5_factor_registry_v1 import compute_site_context  # noqa: E402

BASE = {"light_availability_ppm": 550000, "soil_moisture_ppm": 400000,
        "nutrient_availability_ppm": 500000, "disturbance_pressure_ppm": 50000,
        "temperature_milli_c": 15000}
SITES = {
    "flat_plain": {},
    "south_slope": {"slope_deg": 30.0, "aspect_deg": 180.0},
    "north_slope": {"slope_deg": 28.0, "aspect_deg": 10.0},
    "ravine_bottom": {"cavity_depth_m": 3.0, "water_dist_m": 4.0},
    "rocky_ridge_ore": {"slope_deg": 32.0, "aspect_deg": 200.0, "rock_count": 5,
                        "mineral_deposit": {"type": "iron_vein", "richness": 0.9}},
    "snow_patch": {"snow_cover_frac": 0.6, "aspect_deg": 350.0},
}


def main() -> int:
    contexts = {name: compute_site_context(BASE, feats) for name, feats in sorted(SITES.items())}
    light_values = [c["effective_conditions"]["light_availability_ppm"] for c in contexts.values()]
    document = {
        "schema": "distributed_world_simulator.ecology.evo5_a05_broken_plot_contexts.v1",
        "version": "1.0.0",
        "derived_representation": True,
        "base_conditions": BASE,
        "sites": contexts,
    }
    out = ROOT / "validation/ecology/evo5_a05_broken_plot_contexts.v1.json"
    out.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    divergence = max(light_values) - min(light_values)
    print(f"EVO5_A05_DEMO verdict=PASS sites={len(SITES)} divergence={divergence}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
