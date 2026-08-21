"""ECO EVO3 E3.FINAL precommit fixture generator (deterministic, one-shot).

Materializes the byte-frozen precommit package declared by the E3.FINAL
challenge contract BEFORE any challenge compilation runs:

  - 4 unseen planet field snapshots derived from the accepted alpha-01
    fixture by declared multi-axis integer transforms;
  - 2 persisted SpeciesCatalog variants (extended 12-entry, mono 1-entry)
    whose checksums are computed exclusively through the UNMODIFIED accepted
    E3.4 catalog hashing surface.

No RNG, no clock, no environment reads. The generator never runs the
compilation chain; it only produces inputs and prints identity pins.

Import discipline: causal_colonization_program_compiler_v1.py is loaded by
path and used read-only (hash helpers + validate_catalog). Accepted files are
never modified.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import pathlib
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[3]
STAGE_DIR = ROOT / "config/ecology"
OUT_DIR = ROOT / "config/ecology/accepted_inputs/e3_final"
BASE_SNAPSHOT_PATH = STAGE_DIR / "accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json"
BASE_CATALOG_PATH = STAGE_DIR / "accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
E34_PATH = ROOT / "scripts/research/ecology/causal_colonization_program_compiler_v1.py"

SCALE = 1_000_000


def canonical_bytes(v: Any) -> bytes:
    return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha256_hex(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_hex(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def object_hash(v: dict, field: str) -> str:
    x = copy.deepcopy(v)
    x.pop(field, None)
    return sha256_hex(canonical_bytes(x))


def _clamp(v: int) -> int:
    return 0 if v < 0 else (SCALE if v > SCALE else v)


def _load_e34():
    spec = importlib.util.spec_from_file_location("e34_module_for_precommit", E34_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


PLANET_SPECS = (
    {"slug": "arid-basin-02", "index": "02", "transforms": (("soil_moisture_ppm", "mul", (250_000, 1_000_000)), ("temperature_milli_c", "add", 8_000), ("light_availability_ppm", "mul", (1_200_000, 1_000_000)))},
    {"slug": "oceanic-ridge-03", "index": "03", "transforms": (("soil_moisture_ppm", "mul", (1_500_000, 1_000_000)), ("nutrient_availability_ppm", "mul", (600_000, 1_000_000)), ("disturbance_pressure_ppm", "mul", (300_000, 1_000_000)))},
    {"slug": "polar-plateau-04", "index": "04", "transforms": (("temperature_milli_c", "add", -18_000), ("light_availability_ppm", "mul", (700_000, 1_000_000)), ("disturbance_pressure_ppm", "mul", (1_400_000, 1_000_000)))},
    {"slug": "volcanic-isles-05", "index": "05", "transforms": (("nutrient_availability_ppm", "mul", (1_600_000, 1_000_000)), ("disturbance_pressure_ppm", "mul", (2_200_000, 1_000_000)), ("soil_moisture_ppm", "mul", (900_000, 1_000_000)))},
)

EXTENDED_TRAIT_GRID = tuple(
    {"water_preference": wp / 100.0, "water_tolerance_width": wt / 100.0, "shade_tolerance": st / 100.0}
    for wp, wt, st in (
        (15, 40, 70), (30, 30, 55), (45, 22, 40), (60, 18, 28), (75, 14, 18),
        (85, 10, 10), (25, 26, 62), (50, 16, 48), (68, 20, 33), (92, 8, 6),
    )
)


def build_unseen_snapshot(base: dict, spec: dict) -> dict:
    s = copy.deepcopy(base)
    s["stable_planet_identity"] = f"eco-evo3-final/unseen/{spec['slug']}/planet-alpha-derived-{spec['index']}"
    for x in s["samples"]:
        for axis, kind, arg in spec["transforms"]:
            if kind == "mul":
                num, den = arg
                x[axis] = _clamp(int(x[axis]) * num // den)
            else:
                x[axis] = int(x[axis]) + arg
        x["sample_hash"] = object_hash(x, "sample_hash")
    s["snapshot_id"] = f"eco-evo3/e3.final/precommit/{spec['slug']}/" + object_hash(s, "snapshot_hash")[:24]
    s["snapshot_hash"] = object_hash(s, "snapshot_hash")
    return s


def make_entry(e34, i: int, trait: dict, parent_lineage: str) -> dict:
    genome = {
        "schema": e34.GENOME_SCHEMA,
        "version": e34.CATALOG_VERSION,
        "genome_id": f"genome/e3f-ext-{i:02d}",
        "height_m": round(0.4 + (i % 5) * 0.35, 2),
        "growth_rate": round(0.35 + (i % 4) * 0.2, 2),
        "root_depth_m": round(0.3 + (i % 3) * 0.45, 2),
        "water_preference": trait["water_preference"],
        "water_tolerance_width": trait["water_tolerance_width"],
        "shade_tolerance": trait["shade_tolerance"],
        "seed_count": 120 + 40 * i,
        "seed_dispersal_distance_m": float(8 + 7 * (i % 6)),
        "lifespan_years": float(1 + (i % 5)),
    }
    traits = {
        "schema": e34.RECRUITMENT_SCHEMA,
        "version": e34.CATALOG_VERSION,
        "trait_id": f"recruit/e3f-ext-{i:02d}",
        "dormancy_fraction": round(0.05 + 0.04 * (i % 9), 2),
        "seed_bank_half_life_years": round(0.5 + 0.4 * (i % 6), 1),
    }
    gsum = e34._genome_checksum(genome)
    rsum = e34._recruitment_checksum(traits)
    genome["checksum"] = gsum
    traits["checksum"] = rsum
    lineage = f"eco-lineage/e3f-ext-{i:02d}"
    observation = sha256_hex(canonical_bytes({"genome": genome, "traits": traits}))
    species_id = "eco-research-species/" + sha256_hex((lineage + observation).encode("utf-8"))[:24]
    entry = {
        "schema": e34.CATALOG_ENTRY_SCHEMA,
        "version": e34.CATALOG_VERSION,
        "research_species_id": species_id,
        "lineage_id": lineage,
        "parent_lineage_id": parent_lineage,
        "split_year": 2,
        "genome": genome,
        "genome_checksum": gsum,
        "recruitment_traits": traits,
        "recruitment_traits_checksum": rsum,
        "source_observation_hash": observation,
        "canonical_species_declared": False,
        "ancestry_path": [parent_lineage],
        "observed_patch_ids": [],
    }
    entry["entry_hash"] = e34._entry_hash(entry)
    return entry


def build_extended_catalog(e34, base: dict) -> dict:
    cat = copy.deepcopy(base)
    parent = str(cat["entries"][0]["lineage_id"])
    extra = [make_entry(e34, i, t, parent) for i, t in enumerate(EXTENDED_TRAIT_GRID, start=1)]
    cat["entries"] = sorted(copy.deepcopy(cat["entries"]) + extra, key=lambda e: str(e["research_species_id"]))
    cat["bake_id"] = "eco-evo3-final-precommit/extended-catalog-r1"
    cat["source_run_hash"] = sha256_hex(canonical_bytes({"variant": "extended", "entries": len(cat["entries"]), "grid": EXTENDED_TRAIT_GRID}))
    cat["catalog_hash"] = e34._catalog_hash(cat)
    return cat


def build_mono_catalog(e34, base: dict) -> dict:
    cat = copy.deepcopy(base)
    cat["entries"] = [copy.deepcopy(cat["entries"][0])]
    cat["bake_id"] = "eco-evo3-final-precommit/mono-catalog-r1"
    cat["source_run_hash"] = sha256_hex(canonical_bytes({"variant": "mono", "kept_entry": cat["entries"][0]["entry_hash"]}))
    cat["catalog_hash"] = e34._catalog_hash(cat)
    return cat


def write_json(path: pathlib.Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_bytes(value) + b"\n")


def main() -> int:
    e34 = _load_e34()
    base_snapshot = json.loads(BASE_SNAPSHOT_PATH.read_bytes().decode("utf-8"))
    base_catalog = json.loads(BASE_CATALOG_PATH.read_bytes().decode("utf-8"))

    sanity = e34._catalog_hash(base_catalog)
    print(f"[sanity] baseline catalog_hash recomputed={sanity} expected=5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219")
    if sanity != base_catalog.get("catalog_hash"):
        raise SystemExit("baseline catalog hash mismatch - import discipline broken")

    rows = []
    for spec in PLANET_SPECS:
        snap = build_unseen_snapshot(base_snapshot, spec)
        name = f"e3_final_unseen_planet_field_snapshot.{spec['slug']}.v1.json"
        write_json(OUT_DIR / name, snap)
        raw = (OUT_DIR / name).read_bytes()
        rows.append((name, len(raw), sha256_hex(raw), git_blob_hex(raw), snap["snapshot_hash"]))

    for label, builder in (("extended_r1", build_extended_catalog), ("mono_r1", build_mono_catalog)):
        cat = builder(e34, base_catalog)
        synthetic_contract = {"persisted_evo2_catalog": {"entry_count": len(cat["entries"]), "catalog_hash": cat["catalog_hash"]}}
        e34.validate_catalog(cat, synthetic_contract)
        name = f"evo2_persisted_species_catalog.e3_final_{label}.v1.json"
        write_json(OUT_DIR / name, cat)
        raw = (OUT_DIR / name).read_bytes()
        rows.append((name, len(raw), sha256_hex(raw), git_blob_hex(raw), cat["catalog_hash"]))

    print("\n=== E3.FINAL PRECOMMIT PACKAGE ===")
    for name, size, sha, blob, ident in rows:
        print(f"{name}\n  bytes={size} sha256={sha} blob={blob}")
        print(f"  identity={ident}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
