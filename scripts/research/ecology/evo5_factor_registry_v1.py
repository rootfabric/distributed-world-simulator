"""ECO.EVO5/A0 - Environment Factor Registry (Site Context contract).

effective_conditions(site) = base_sample (+) SUM(modifiers), applied in
canonical factor_id order; modifiers are pure functions of DECLARED inputs;
deltas are integer ppm clamped to [0, 1_000_000] for availability channels and
signed milli-units for temperature_milli_c. Adding a factor = data via
register_factor(); no compiler edits. Research layer only.
"""
from __future__ import annotations

import sys

AVAILABILITY_CHANNELS = (
    "light_availability_ppm",
    "soil_moisture_ppm",
    "nutrient_availability_ppm",
    "disturbance_pressure_ppm",
    "establishment_bonus_ppm",
    "mineral_richness_ppm",
)
TEMP_CHANNEL = "temperature_milli_c"
PPM_MAX = 1_000_000


def _clamp_ppm(value: int) -> int:
    return max(0, min(PPM_MAX, value))


REGISTRY: dict[str, dict] = {
    "aspect_north": {"inputs": ["aspect_deg"], "apply": lambda f: {TEMP_CHANNEL: -2500 if float(f.get("aspect_deg", 180.0)) > 270.0 or float(f.get("aspect_deg", 180.0)) < 90.0 else 1500}},
    "slope": {"inputs": ["slope_deg"], "apply": lambda f: ({"light_availability_ppm": -60000, "soil_moisture_ppm": -80000} if float(f.get("slope_deg", 0.0)) > 25.0 else {})},
    "cavity_shade": {"inputs": ["cavity_depth_m"], "apply": lambda f: ({"light_availability_ppm": -220000, "soil_moisture_ppm": 90000, TEMP_CHANNEL: -3500} if float(f.get("cavity_depth_m", 0.0)) > 1.0 else {})},
    "mineral_deposit": {"inputs": ["mineral_deposit"], "apply": lambda f: ({"mineral_richness_ppm": int(400000 * float((f["mineral_deposit"] or {}).get("richness", 0.8)))} if f.get("mineral_deposit") else {})},
    "rock": {"inputs": ["rock_count"], "apply": lambda f: ({"light_availability_ppm": -30000, "establishment_bonus_ppm": 50000} if int(f.get("rock_count", 0)) > 0 else {})},
    "snow_cover": {"inputs": ["snow_cover_frac"], "apply": lambda f: ({"temperature_milli_c": -6000, "soil_moisture_ppm": 70000} if float(f.get("snow_cover_frac", 0.0)) > 0.05 else {})},
    "water_proximity": {"inputs": ["water_dist_m"], "apply": lambda f: ({"soil_moisture_ppm": 150000, "nutrient_availability_ppm": 60000} if float(f.get("water_dist_m", 9999.0)) < 8.0 else {})},
}


def register_factor(name: str, inputs: list[str], apply_fn) -> None:
    """Data-only extension point: future surface generators add factors without code edits."""
    if name in REGISTRY:
        raise ValueError(f"factor already registered: {name}")
    if not callable(apply_fn) or not inputs:
        raise ValueError("factor spec requires non-empty inputs list and callable apply")
    REGISTRY[name] = {"inputs": list(inputs), "apply": apply_fn}


def compute_site_context(base_conditions: dict, site_features: dict) -> dict:
    effective = {k: int(v) for k, v in base_conditions.items()}
    applied = []
    for factor_id in sorted(REGISTRY.keys()):
        spec = REGISTRY[factor_id]
        if any(input_name not in site_features for input_name in spec["inputs"]):
            continue  # fail-closed: factor acts only on present declared inputs
        deltas = spec["apply"](site_features) or {}
        if not deltas:
            continue
        for channel, delta in deltas.items():
            if channel == TEMP_CHANNEL:
                effective[channel] = int(effective.get(channel, 15000)) + int(delta)
            elif channel in AVAILABILITY_CHANNELS:
                effective[channel] = _clamp_ppm(int(effective.get(channel, PPM_MAX // 2)) + int(delta))
            else:
                raise ValueError(f"unknown channel declared by factor {factor_id}: {channel}")
        applied.append({"factor_id": factor_id, "deltas": dict(sorted(deltas.items()))})
    return {"effective_conditions": effective, "applied_factors": applied}


if __name__ == "__main__":
    demo = compute_site_context(
        {"light_availability_ppm": 550000, "soil_moisture_ppm": 400000,
         "nutrient_availability_ppm": 500000, "disturbance_pressure_ppm": 50000},
        {"cavity_depth_m": 2.0, "water_dist_m": 3.0},
    )
    print("EVO5_FACTOR_REGISTRY smoke:", demo["applied_factors"])
    sys.exit(0)
