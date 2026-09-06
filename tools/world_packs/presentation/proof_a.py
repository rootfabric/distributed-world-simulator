"""Proof A (contract level): SAME CANONICAL WORLD -> DIFFERENT PRESENTATION.

This is a non-runtime preparation fixture. It proves, at the WP2.0 contract
level, that switching an artistic presentation recipe changes ONLY the
presentation selection (surface family, variant, scale, presentation lock)
while every available canonical invariant stays byte-identical.

Honesty notes (no fabricated invariants):
- world generation identity is a MOCK deterministic function of (seed,
  profile) because WORLDGEN1 is design-only (see wp2_activation_state.v1.json);
- Matter snapshot identity hashes the read-only catalog snapshot file;
- geometry source identity hashes the deterministic surface sample geometry
  (positions/normals), the strongest geometry invariant available without a
  runtime mesh owner;
- collision identity and mutation log identity are NOT exercised in this
  contract fixture (no runtime); they are recorded as NOT_AVAILABLE rather
  than invented.
- recipe A vs B is artistic presentation only. matter/basalt remains
  physically matter/basalt under both recipes.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from .contract import ClientFidelity, WorldSurfacePresentationInput, canonical_input_hash
from .resolver import CATALOG_SNAPSHOT_PATH, RECIPES_PATH, SurfacePresentationResolver

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = REPO_ROOT / "fixtures" / "world_packs" / "proof_a" / "proof_a_contract_fixture.v1.json"

RECIPE_A = "recipe/wp2-proof-a-dark-basaltic@1.0.0"
RECIPE_B = "recipe/wp2-proof-a-light-dusty@1.0.0"
SEEDS = (11, 29, 47)
PROFILE = "moon-industrial-like@mock-0.1.0"


def _sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _seed_worldgen_identity(seed: int) -> str:
    # MOCK generation identity: deterministic stand-in until WORLDGEN1 is
    # executable. Clearly labelled; never presented as a real generator hash.
    return _sha256_hex(f"MOCK-WORLDGEN|{PROFILE}|seed={seed}")


def _samples_for_seed(seed: int):
    """Deterministic canonical surface samples covering several materials and frames."""
    samples = []
    # Same canonical world shape per seed: layering pattern over a body-fixed strip.
    layout = [
        ("matter/regolith-loose", (0.0, 0.0, 1.0), (0.0, 0.0, -1.0)),      # horizontal floor, gravity down
        ("matter/regolith-compacted", (0.6, 0.0, 0.8), (0.0, 0.0, -1.0)),  # sloped
        ("matter/basalt", (1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),              # vertical wall
        ("matter/fractured-basalt", (-0.5, 0.0, -0.87), (0.0, 0.0, -1.0)), # overhang
        ("matter/water-ice", (0.0, 0.0, -1.0), (0.0, 0.0, -1.0)),          # cave ceiling (inward)
        ("matter/iron-nickel-ore", (0.7, 0.7, 0.1), None),                 # irregular asteroid facet, weak gravity
    ]
    for index, (material, normal, gravity) in enumerate(layout):
        coord = 16.0 * seed + index
        samples.append(WorldSurfacePresentationInput(
            body_id="body/mock-moon",
            surface_id=f"surface/seed{seed}/{index}",
            position_body_fixed=(coord * 0.37, coord * 0.11, coord * 0.73),
            material_id=material,
            composition={"canonical": 1.0},
            surface_state="as-generated",
            matter_revision=seed,
            surface_normal=normal,
            gravity_direction=gravity,
            representation_revision=seed,
            exposure_state=None,
        ))
    return samples


def _matter_snapshot_identity() -> str:
    return hashlib.sha256(CATALOG_SNAPSHOT_PATH.read_bytes()).hexdigest()


def _geometry_source_identity(samples) -> str:
    blob = json.dumps([
        {"surface_id": s.surface_id,
         "position_body_fixed": list(s.position_body_fixed),
         "surface_normal": list(s.surface_normal)}
        for s in samples
    ], sort_keys=True, separators=(",", ":"))
    return _sha256_hex(blob)


def build_fixture() -> dict:
    resolver = SurfacePresentationResolver()
    matter_identity = _matter_snapshot_identity()
    seeds = []
    for seed in SEEDS:
        samples = _samples_for_seed(seed)
        canonical_hashes = [canonical_input_hash(s) for s in samples]
        geometry_identity = _geometry_source_identity(samples)
        entries = []
        for index, sample in enumerate(samples):
            selection_a = resolver.resolve(sample, ClientFidelity("high"), recipe_ref=RECIPE_A)
            selection_b = resolver.resolve(sample, ClientFidelity("high"), recipe_ref=RECIPE_B)
            client_a = resolver.resolve(sample, ClientFidelity("preview"), recipe_ref=RECIPE_A)
            entries.append({
                "surface_id": sample.surface_id,
                "material_id": sample.material_id,
                "canonical_input_hash": canonical_hashes[index],
                "selection_recipe_a": selection_a.to_json(),
                "selection_recipe_b": selection_b.to_json(),
                "selection_client_preview": client_a.to_json(),
            })
            # Core Proof A invariant, enforced at build time:
            assert canonical_hashes[index] == canonical_input_hash(sample)
            assert selection_a.presentation_lock != selection_b.presentation_lock
            assert selection_a.surface_family != selection_b.surface_family
        seeds.append({
            "seed": seed,
            "generation_profile": PROFILE,
            "invariants": {
                "world_generation_identity_mock": _seed_worldgen_identity(seed),
                "matter_snapshot_identity": matter_identity,
                "geometry_source_identity": geometry_identity,
                "canonical_input_hashes": canonical_hashes,
                "collision_identity": "NOT_AVAILABLE_IN_CONTRACT_FIXTURE",
                "mutation_log_identity": "NOT_EXERCISED_IN_CONTRACT_FIXTURE",
            },
            "surfaces": entries,
        })
    return {
        "schema": "distributed_world_simulator.world_packs.proof_a_contract_fixture.v1",
        "proof": "SAME_CANONICAL_WORLD_DIFFERENT_PRESENTATION",
        "claim": "Recipe A (dark basaltic artistic) and Recipe B (light dusty artistic) over the same canonical inputs change presentation selection only. No claim is made that matter/basalt physically became sandstone; this is presentation only.",
        "runtime_status": "contract-level fixture; runtime activation is BLOCKED per config/world_packs/wp2_activation_state.v1.json",
        "recipe_a": RECIPE_A,
        "recipe_b": RECIPE_B,
        "seeds": seeds,
    }


def write_fixture(path: Path = FIXTURE_PATH) -> str:
    fixture = build_fixture()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(fixture, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
                    encoding="utf-8")
    return hashlib.sha256(json.dumps(fixture, sort_keys=True, ensure_ascii=False)
                          .encode("utf-8")).hexdigest()


if __name__ == "__main__":
    digest = write_fixture()
    print(f"proof-a fixture written: {FIXTURE_PATH}")
    print(f"stable-content sha256: {digest}")
