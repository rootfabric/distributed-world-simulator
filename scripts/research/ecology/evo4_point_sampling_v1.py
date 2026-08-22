"""ECO.EVO4/E4.B5 - deterministic nearest-sample point sampling (pure module).

Contract: docs/plans/ECO_EVO4_B5_POINT_SAMPLING_CONTRACT_RU.md
Grounded in accepted E3.FINAL unseen planet field snapshots whose samples carry
latitude_microdeg / longitude_microdeg geometry and ppm/milli-c condition keys.
No IO, no clock, no randomness; identical inputs produce identical results.
"""
from __future__ import annotations

import math

CONDITION_KEYS = (
    "disturbance_pressure_ppm",
    "light_availability_ppm",
    "nutrient_availability_ppm",
    "soil_moisture_ppm",
    "temperature_milli_c",
)
GEOMETRY_KEYS = ("latitude_microdeg", "longitude_microdeg")
IDENTITY_KEYS = ("sample_id", "stable_spatial_key")
LAT_EXTENT = (-90_000_000.0, 90_000_000.0)
LON_EXTENT = (-180_000_000.0, 180_000_000.0)

ERROR_EMPTY_INDEX = "EVO4_SAMPLE_EMPTY_INDEX"
ERROR_NONFINITE_POINT = "EVO4_SAMPLE_NONFINITE_POINT"
ERROR_OUT_OF_EXTENT = "EVO4_SAMPLE_OUT_OF_EXTENT"


def build_sample_index(samples: list[dict]) -> dict:
    """Validate minimal sample shape and freeze a stable, ordered index."""
    frozen = []
    for item in samples:
        for key in GEOMETRY_KEYS + IDENTITY_KEYS:
            if key not in item:
                raise ValueError(f"sample missing required key: {key}")
        for key in CONDITION_KEYS:
            if key not in item:
                raise ValueError(f"sample missing condition key: {key}")
        frozen.append({key: item[key] for key in sorted(item.keys())})
    frozen.sort(key=lambda s: str(s["stable_spatial_key"]))
    return {"samples": tuple(frozen)}


def _is_real_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def sample(index: dict, latitude_microdeg, longitude_microdeg) -> dict:
    candidates = index.get("samples", ())
    if len(candidates) == 0:
        return {"ok": False, "error_code": ERROR_EMPTY_INDEX}
    for value in (latitude_microdeg, longitude_microdeg):
        if not _is_real_number(value):
            return {"ok": False, "error_code": ERROR_NONFINITE_POINT}
        if not math.isfinite(float(value)):
            return {"ok": False, "error_code": ERROR_NONFINITE_POINT}
    lat = float(latitude_microdeg)
    lon = float(longitude_microdeg)
    if lat < LAT_EXTENT[0] or lat > LAT_EXTENT[1] or lon < LON_EXTENT[0] or lon > LON_EXTENT[1]:
        return {"ok": False, "error_code": ERROR_OUT_OF_EXTENT}
    best = None
    best_key = None
    best_distance = None
    for candidate in candidates:
        delta_lat = float(candidate["latitude_microdeg"]) - lat
        delta_lon = float(candidate["longitude_microdeg"]) - lon
        distance_squared = delta_lat * delta_lat + delta_lon * delta_lon
        sort_key = (distance_squared, str(candidate["stable_spatial_key"]))
        if best_key is None or sort_key < best_key:
            best = candidate
            best_key = sort_key
            best_distance = distance_squared
    return {
        "ok": True,
        "stable_spatial_key": best["stable_spatial_key"],
        "sample_id": best["sample_id"],
        "distance_squared_microdeg2": best_distance,
        "conditions": {key: best[key] for key in CONDITION_KEYS},
    }
