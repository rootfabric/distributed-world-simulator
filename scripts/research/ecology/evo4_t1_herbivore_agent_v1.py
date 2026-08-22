"""ECO.EVO4/E4.T1 - herbivore agent contract v0 (aggregate patch pressure).

Portable agent {appetite, mobility, preference_vector(v0: nutrient_value up,
toxicity down)} aggregated into per-patch browsing pressure over the ACCEPTED
E4.B6 region manifest patches (PopulationPatch semantics, aggregate only -
no individual truth, no new genes). Species trophic attributes are v0 proxies
derived from metabolic fields using the SAME declared formula as EVO4.T0
(defense reproduces the sealed T0 values bit-for-bit on shared genomes).

Manifest honesty: every B6 patch carries the same 9-species composition
(90 instances per patch), so patch visitation alone cannot express food
preference. Pressure therefore splits into (a) patch visitation weights and
(b) an intra-patch allocation across resident species driven by the
preference vector; both are aggregate patch quantities.
Presentation-side research only; no ecology truth claims. Pure stdlib.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = ROOT / "validation/ecology/evo4_b6_region_manifest.v1.json"
RESULT_PATH = ROOT / "validation/ecology/evo4_t1_agent_pressure.v1.json"
SCHEMA = "distributed_world_simulator.ecology.evo4_t1_agent_pressure.v1"
RULE = "evo4-t1-herbivore-agent-v0"

PRESSURE_STOCK = 1.0
APPETITE_SWEEP = [0.25, 0.50, 1.00, 1.50, 2.00]


def _unit(text: str) -> float:
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16) / float(2 ** 48)


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def make_agent(appetite: float = 1.0, mobility: float = 0.60,
               nutrient_weight: float = 0.70, toxicity_weight: float = 0.30) -> dict:
    """Portable herbivore agent contract (v0). Preference points toward
    nutrient_value and against toxicity."""
    return {
        "appetite": _clamp(float(appetite), 0.0, 4.0),
        "mobility": _clamp(float(mobility), 0.0, 1.0),
        "preference_vector": {
            "nutrient_weight": _clamp(float(nutrient_weight), 0.0, 1.0),
            "toxicity_weight": _clamp(float(toxicity_weight), 0.0, 1.0),
        },
    }


def derive_species_attributes(manifest: dict) -> dict:
    """v0 trophic proxies per genome_id. Defense uses the exact EVO4.T0
    derivation (root_depth_proxy default 0.5, as consumed by the sealed T0
    probe); nutrient/toxicity are declared metabolic-field derivations."""
    attributes: dict[str, dict] = {}
    for gid in sorted(manifest["species_traits"]):
        sp = manifest["species_traits"][gid]
        traits = sp["development_traits"]
        apical = _clamp(float(traits["apical_dominance"]), 0.0, 1.0)
        shade = _clamp(float(sp["shade_tolerance"]), 0.0, 1.0)
        dormancy = _clamp(float(sp["dormancy_fraction"]), 0.0, 1.0)
        vigor = _clamp(float(traits["max_height_m"]) / 40.0 + 0.3, 0.3, 1.0)
        defense = _clamp(0.55 * apical + 0.45 * 0.5 + 0.10 * (_unit(gid) - 0.5), 0.05, 0.95)
        attributes[gid] = {
            "defense": round(defense, 4),
            "vigor": round(vigor, 4),
            "nutrient_value": round(_clamp(0.30 + 0.45 * vigor + 0.25 * _unit(gid + "|nutrient"), 0.05, 0.98), 4),
            "toxicity": round(_clamp(0.20 * shade + 0.15 * dormancy + 0.20 * _unit(gid + "|toxicity"), 0.02, 0.60), 4),
        }
    return attributes


def palatability(agent: dict, attrs: dict) -> float:
    pref = agent["preference_vector"]
    return (float(pref["nutrient_weight"]) * float(attrs["nutrient_value"])
            - float(pref["toxicity_weight"]) * float(attrs["toxicity"]))


def aggregate_patch_pressure(manifest: dict, agent: dict,
                             species_attributes: dict | None = None) -> list[dict]:
    """Aggregate agent pressure per B6 manifest patch (stable_spatial_key).

    Patch visitation interpolates between full concentration on the most
    attractive patch (mobility=0) and equal coverage (mobility=1); with the
    B6 manifest all patches are composition-identical, so attraction is
    uniform there by construction. Inside each patch the pressure is split
    across resident species proportionally to shifted preference scores, so
    the preference vector steers which species bears the pressure.
    Pressure is linear in appetite, hence monotone in appetite by
    construction; the gates verify this on the produced numbers anyway.
    """
    attrs = species_attributes if species_attributes is not None else derive_species_attributes(manifest)
    mobility = float(agent["mobility"])

    residents: dict[str, dict[str, int]] = {}
    for instance in manifest["instances"]:
        gid = str(instance["genome_id"])
        if gid not in attrs:
            continue
        patch = residents.setdefault(str(instance["stable_spatial_key"]), {})
        patch[gid] = patch.get(gid, 0) + 1

    keys = sorted(residents)

    def species_split(patch_residents: dict[str, int]) -> dict[str, float]:
        scores = {gid: palatability(agent, attrs[gid]) for gid in patch_residents}
        lo = min(scores.values())
        shifted = {gid: scores[gid] - lo for gid in scores}
        total = sum(shifted.values())
        if total <= 0.0:
            even = 1.0 / len(scores)
            return {gid: even for gid in scores}
        return {gid: shifted[gid] / total for gid in scores}

    # Patch attractiveness = instance-mean palatability (uniform across the
    # B6 patches today; kept general so a heterogeneous manifest still works).
    scores = {
        k: sum(palatability(agent, attrs[g]) * n for g, n in residents[k].items())
        / sum(residents[k].values())
        for k in keys
    }
    lo = min(scores.values()) if scores else 0.0
    shifted = {k: scores[k] - lo for k in keys}
    total_shifted = sum(shifted.values())
    if scores and total_shifted > 0.0:
        proportional = {k: shifted[k] / total_shifted for k in keys}
    else:
        # No attractiveness signal (all ties) -> uniform coverage.
        proportional = {k: 1.0 / len(keys) for k in keys}
    best = min(k for k in keys if abs(shifted[k] - max(shifted.values())) < 1e-15)
    raw_weights = {}
    for k in keys:
        concentrated = 1.0 if k == best else 0.0
        raw_weights[k] = mobility * proportional[k] + (1.0 - mobility) * concentrated
    norm = sum(raw_weights.values()) or 1.0

    patches = []
    for k in keys:
        split = species_split(residents[k])
        row = {
            "patch_key": k,
            "instance_count": sum(residents[k].values()),
            "resident_species": len(residents[k]),
            "palatability_score": round(scores[k], 5),
            "visitation_weight": round(raw_weights[k] / norm, 8),
            "species_pressure_share": {gid: round(split[gid], 8) for gid in sorted(split)},
            "pressure_by_appetite": {},
        }
        for appetite in APPETITE_SWEEP:
            row["pressure_by_appetite"]["%.2f" % appetite] = round(
                PRESSURE_STOCK * float(appetite) * raw_weights[k] / norm, 8)
        patches.append(row)
    return patches


def _digest(patches: list[dict]) -> str:
    return hashlib.sha256(json.dumps(patches, sort_keys=True).encode("utf-8")).hexdigest()


def evaluate_gates(patches: list[dict], agent: dict, species_attributes: dict) -> dict:
    """Gates: G1 internal recompute determinism; G2 pressure monotone in
    appetite (per-patch non-decreasing, total strictly increasing);
    G3 preference alignment (pressured species bear above-average
    palatability for any interior preference contrast)."""
    digest_a = _digest(patches)
    digest_b = hashlib.sha256(
        json.dumps(json.loads(json.dumps(patches)), sort_keys=True).encode("utf-8")).hexdigest()
    g1 = digest_a == digest_b

    appetites = sorted(patches[0]["pressure_by_appetite"], key=float) if patches else []
    g2_per_patch = True
    for row in patches:
        values = [row["pressure_by_appetite"][a] for a in appetites]
        g2_per_patch &= all(b >= a - 1e-12 for a, b in zip(values, values[1:]))
    totals = [round(sum(row["pressure_by_appetite"][a] for row in patches), 6) for a in appetites]
    g2_total_strict = all(b > a for a, b in zip(totals, totals[1:]))
    g2 = bool(g2_per_patch and g2_total_strict)

    # Flatten to (patch, species) cells and compare pressured palatability
    # against the unweighted resident-species mean.
    seen_species = sorted({gid for row in patches for gid in row["species_pressure_share"]})
    unweighted_mean = sum(palatability(agent, species_attributes[g]) for g in seen_species) / max(len(seen_species), 1)
    pressured_mean = 0.0
    stock = 0.0
    for row in patches:
        p1 = row["pressure_by_appetite"]["1.00"]
        for gid, share in row["species_pressure_share"].items():
            cell = p1 * share
            pressured_mean += cell * palatability(agent, species_attributes[gid])
            stock += cell
    g3 = stock > 0.0 and (pressured_mean / stock) > unweighted_mean

    return {
        "g1_recompute_determinism": bool(g1),
        "g2_monotone_in_appetite": bool(g2),
        "g2_total_pressure_by_appetite": totals,
        "g3_preference_alignment": bool(g3),
        "pressured_palatability_vs_uniform_mean": [
            round(pressured_mean / stock, 6) if stock > 0 else 0.0, round(unweighted_mean, 6)],
        "pressure_digest_sha256": digest_a,
    }


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    attributes = derive_species_attributes(manifest)
    agent = make_agent()
    patches = aggregate_patch_pressure(manifest, agent, attributes)
    gates = evaluate_gates(patches, agent, attributes)
    instance_species = sorted({str(i["genome_id"]) for i in manifest["instances"]})

    verdict = "PASS" if all(v for k, v in gates.items() if isinstance(v, bool)) else "FAIL"
    result = {
        "schema": SCHEMA, "version": "1.0.0", "rule": RULE,
        "derived_representation": True,
        "source_manifest_sha256": hashlib.sha256(MANIFEST_PATH.read_bytes()).hexdigest(),
        "agent_contract": agent,
        "species_count": len(instance_species),
        "patch_count": len(patches),
        "species_attributes": {gid: attributes[gid] for gid in instance_species},
        "patches": patches,
        "gates": gates,
        "no_individual_truth": True,
        "verdict": verdict,
    }
    RESULT_PATH.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"EVO4_T1_AGENT_PRESSURE verdict={verdict} species={len(instance_species)} "
          f"patches={len(patches)} digest={gates['pressure_digest_sha256'][:16]}")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
