"""ECO.EVO6-WATER/R1 deterministic water availability + genome fitness model.

This is a research reference for the Godot selection adapter. It consumes
existing water observations and existing plant genome traits; it does not own
water simulation, mutation, or lineage truth.
"""
from __future__ import annotations

import math

MIN_FITNESS = 0.05
MAX_FITNESS = 4.0
DEFAULT_SOIL_MOISTURE_PPM = 400_000.0


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def water_availability(site: dict) -> float:
    features = site.get("features", site)
    conditions = site.get("effective_conditions", site)
    if bool(features.get("in_water", False)):
        return 1.0
    moisture = float(conditions.get("soil_moisture_ppm", DEFAULT_SOIL_MOISTURE_PPM)) / 1_000_000.0
    moisture = _clamp(moisture, 0.0, 1.0)
    if "water_dist_m" not in features:
        return moisture
    distance = max(0.0, float(features["water_dist_m"]))
    proximity = math.exp(-distance / 3.0)
    return _clamp(max(moisture, 0.15 + 0.75 * proximity), 0.0, 1.0)


def evaluate(genome: dict, site: dict) -> dict:
    features = site.get("features", site)
    surface_water = water_availability(site)
    preference = _clamp(float(genome.get("water_preference", 0.5)), 0.0, 1.0)
    tolerance = _clamp(float(genome.get("water_tolerance_width", 0.30)), 0.02, 1.0)
    root_depth = max(0.05, float(genome.get("root_depth_m", 0.85)))

    dryness = _clamp((0.45 - surface_water) / 0.45, 0.0, 1.0)
    root_depth_factor = _clamp((root_depth - 0.35) / 2.65, 0.0, 1.0)
    root_water_gain = dryness * root_depth_factor * 0.18
    effective_water = _clamp(surface_water + root_water_gain, 0.0, 1.0)

    delta = abs(effective_water - preference)
    tolerance_half_width = max(0.02, tolerance * 0.5)
    stress = max(0.0, delta - tolerance_half_width)
    match = math.exp(-12.0 * stress * stress)
    fitness = 0.05 + 2.95 * match

    if bool(features.get("in_water", False)):
        fitness *= 1.20 if preference >= 0.65 else 0.08

    if surface_water < 0.25:
        if root_depth < 0.70:
            fitness *= 0.30
        else:
            fitness *= 1.0 + min(0.80, (root_depth - 0.70) * 0.32)

    fitness = _clamp(fitness, MIN_FITNESS, MAX_FITNESS)
    return {
        "fitness": round(fitness, 9),
        "surface_water": round(surface_water, 9),
        "effective_water": round(effective_water, 9),
        "water_stress": round(stress, 9),
        "root_water_gain": round(root_water_gain, 9),
    }
