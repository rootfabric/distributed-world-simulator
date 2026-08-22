"""ECO.EVO4/E4.T2 - plant-defense x herbivore-preference coevolution loop v0.

40 generations on the 9 bridge species of the ACCEPTED E4.B6 manifest.
Plants shift a defense distribution, agents shift their preference-driven
pressure allocation. Payoffs inherit the SEALED EVO4.T0 structure (constants
DEFENSE_COST=0.35, HERBIVORY_GAIN=0.85; endpoints identical to T0) with a
declared v0 quadratic saturation between endpoints so interior defense
levels have well-defined best responses.

Gates (PH3C-analogue + determinism + robustness):
  G1 no pure-strategy dominance: both pure communities (all-undefended and
     all-fully-defended) are invadable by a best-response mutant under
     adapted agent pressure;
  G2 restart determinism: two independent in-process reruns produce
     byte-identical canonical digests;
  G3 robustness across 3 seeds: every seed passes G1-style invasion checks.

Research only; no ecology truth claims; no new genes; no individual truth.
Pure stdlib.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))
from evo4_t1_herbivore_agent_v1 import (  # noqa: E402
    MANIFEST_PATH,
    _clamp,
    _unit,
    derive_species_attributes,
)

TRAJECTORY_PATH = ROOT / "validation/ecology/evo4_t2_coevolution_trajectory.v1.json"
RESULT_PATH = ROOT / "validation/ecology/evo4_t2_coevolution_result.v1.json"
SCHEMA = "distributed_world_simulator.ecology.evo4_t2_coevolution.v1"

GENERATIONS = 40
DEFENSE_COST = 0.35          # exact EVO4.T0 constant
HERBIVORY_GAIN = 0.85        # exact EVO4.T0 constant
APPETITE = 1.0
PREF_FLOOR = 0.02
PREF_ETA = 0.35
MUTATION_RATE = 0.20
DEFENSE_GRID = [round(0.05 * i, 2) for i in range(21)]
ADAPT_GENS = 12
MAIN_SEED = 20260822
ROBUSTNESS_SEEDS = [20260822, 20260823, 20260824]


def payoff(vigor: float, defense: float, pressure: float) -> float:
    """T0 payoff structure with declared v0 quadratic saturation.
    At defense in {0.0, 1.0} the endpoints equal the sealed T0 form."""
    return vigor - DEFENSE_COST * defense * defense - HERBIVORY_GAIN * pressure * (1.0 - defense) ** 2


def best_response(vigor: float, pressure: float) -> float:
    return max(DEFENSE_GRID, key=lambda c: (payoff(vigor, c, pressure), -c))


def initial_state(seed: int, species: list[str]) -> tuple[dict, dict]:
    defenses = {gid: min(DEFENSE_GRID, key=lambda c: (abs(c - (0.05 + 0.10 * _unit(f"{seed}|{gid}|x0"))),))
                for gid in species}
    prefs = {gid: 1.0 / len(species) for gid in species}
    return defenses, prefs


def allocate_pressure(prefs: dict) -> dict:
    total = sum(max(prefs[gid], PREF_FLOOR) for gid in prefs)
    return {gid: APPETITE * max(prefs[gid], PREF_FLOOR) / total for gid in prefs}


def update_preferences(prefs: dict, defenses: dict, attrs: dict, pressures: dict) -> dict:
    utilities = {}
    for gid, p in pressures.items():
        realized_bites = p * (1.0 - defenses[gid]) ** 2
        utilities[gid] = realized_bites * attrs[gid]["nutrient_value"] - p * attrs[gid]["toxicity"]
    scale = max((abs(u) for u in utilities.values()), default=1.0) or 1.0
    updated = {}
    for gid, u in utilities.items():
        updated[gid] = _clamp(PREF_FLOOR + max(0.0, prefs[gid] + PREF_ETA * (u / scale)), PREF_FLOOR, 1.0)
    norm = sum(updated.values()) or 1.0
    return {gid: updated[gid] / norm for gid in updated}


def mutate(defenses: dict, seed: int, generation: int, species: list[str]) -> dict:
    out = {}
    for gid in species:
        level = defenses[gid]
        if _unit(f"{seed}|{generation}|{gid}|mut") < MUTATION_RATE:
            step = -0.05 if _unit(f"{seed}|{generation}|{gid}|dir") < 0.5 else 0.05
            level = _clamp(round(level + step, 2), 0.0, 1.0)
            level = min(DEFENSE_GRID, key=lambda c: (abs(c - level),))
        out[gid] = level
    return out


def plants_respond(defenses: dict, attrs: dict, pressures: dict,
                   seed: int, generation: int, species: list[str]) -> dict:
    responded = {gid: best_response(attrs[gid]["vigor"], pressures[gid]) for gid in species}
    return mutate(responded, seed, generation, species)


def classify(level: float) -> str:
    if level < 0.2:
        return "NONE"
    if level < 0.4:
        return "LIGHT"
    if level < 0.6:
        return "MODERATE"
    if level < 0.8:
        return "HIGH"
    return "FULL"


def simulate(seed: int, species: list[str], attrs: dict) -> dict:
    defenses, prefs = initial_state(seed, species)
    trajectory = []
    for generation in range(GENERATIONS):
        pressures = allocate_pressure(prefs)
        intake = sum(
            pressures[gid] * attrs[gid]["nutrient_value"] * (1.0 - defenses[gid]) ** 2
            for gid in species)
        mean_payoff = sum(payoff(attrs[gid]["vigor"], defenses[gid], pressures[gid])
                          for gid in species) / len(species)
        histogram = {"NONE": 0, "LIGHT": 0, "MODERATE": 0, "HIGH": 0, "FULL": 0}
        for gid in species:
            histogram[classify(defenses[gid])] += 1
        trajectory.append({
            "generation": generation,
            "mean_defense": round(sum(defenses.values()) / len(species), 6),
            "defense_histogram": histogram,
            "total_agent_intake": round(intake, 6),
            "mean_plant_payoff": round(mean_payoff, 6),
            "pressure_entropy": round(-sum(
                (p * math.log(p) for p in allocate_pressure(prefs).values() if p > 1e-12)), 6),
        })
        defenses = plants_respond(defenses, attrs, pressures, seed, generation, species)
        prefs = update_preferences(prefs, defenses, attrs, allocate_pressure(prefs))
    final_pressures = allocate_pressure(prefs)
    equilibrium = {
        "final_defense": {gid: round(defenses[gid], 2) for gid in species},
        "final_preferences": {gid: round(prefs[gid], 6) for gid in species},
        "final_pressure": {gid: round(final_pressures[gid], 6) for gid in species},
    }
    return {"trajectory": trajectory, "equilibrium": equilibrium}


def invasion_checks(seed: int, species: list[str], attrs: dict) -> dict:
    """Both pure communities must be invadable under adapted agent pressure."""
    results = {}
    for label, fixed_level in (("no_defense_invadable", 0.0), ("full_defense_invadable", 1.0)):
        defenses = {gid: fixed_level for gid in species}
        prefs = {gid: 1.0 / len(species) for gid in species}
        for generation in range(ADAPT_GENS):
            pressures = allocate_pressure(prefs)
            prefs = update_preferences(prefs, defenses, attrs, pressures)
        pressures = allocate_pressure(prefs)
        invadable = False
        evidence = {}
        for gid in species:
            resident = payoff(attrs[gid]["vigor"], fixed_level, pressures[gid])
            mutant_level = best_response(attrs[gid]["vigor"], pressures[gid])
            mutant = payoff(attrs[gid]["vigor"], mutant_level, pressures[gid])
            evidence[gid] = {
                "resident_payoff": round(resident, 6),
                "mutant_defense": mutant_level,
                "mutant_payoff": round(mutant, 6),
            }
            if mutant > resident + 1e-9:
                invadable = True
        results[label] = {"invadable": invadable, "species": evidence}
    return results


def _canonical(obj) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))


def run_pipeline() -> dict:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    attrs_all = derive_species_attributes(manifest)
    species = sorted({str(i["genome_id"]) for i in manifest["instances"]})
    attrs = {gid: attrs_all[gid] for gid in species}

    main = simulate(MAIN_SEED, species, attrs)
    replay = simulate(MAIN_SEED, species, attrs)
    digest_main = hashlib.sha256(_canonical(main).encode("utf-8")).hexdigest()
    digest_replay = hashlib.sha256(_canonical(replay).encode("utf-8")).hexdigest()

    per_seed = {}
    for seed in ROBUSTNESS_SEEDS:
        checks = invasion_checks(seed, species, attrs)
        per_seed[str(seed)] = {
            "no_defense_invadable": checks["no_defense_invadable"]["invadable"],
            "full_defense_invadable": checks["full_defense_invadable"]["invadable"],
        }
        if seed == MAIN_SEED:
            main_checks = checks

    return {
        "manifest_source_sha256": hashlib.sha256(MANIFEST_PATH.read_bytes()).hexdigest(),
        "species": species,
        "species_attributes": attrs,
        "main": main,
        "main_invasion_checks": main_checks,
        "per_seed_gates": per_seed,
        "digest_main": digest_main,
        "digest_replay": digest_replay,
    }


def evaluate_gates(pipeline: dict) -> dict:
    checks = pipeline["main_invasion_checks"]
    g1 = {
        "no_defense_invadable": checks["no_defense_invadable"]["invadable"],
        "full_defense_invadable": checks["full_defense_invadable"]["invadable"],
        "evidence": {
            "no_defense_top": max(
                checks["no_defense_invadable"]["species"].items(),
                key=lambda kv: kv[1]["mutant_payoff"] - kv[1]["resident_payoff"]),
            "full_defense_top": max(
                checks["full_defense_invadable"]["species"].items(),
                key=lambda kv: kv[1]["mutant_payoff"] - kv[1]["resident_payoff"]),
        },
    }
    g2 = pipeline["digest_main"] == pipeline["digest_replay"]
    g3 = all(v["no_defense_invadable"] and v["full_defense_invadable"]
             for v in pipeline["per_seed_gates"].values())
    return {"g1_no_pure_strategy_dominance": g1, "g2_restart_determinism_byte_equal": bool(g2),
            "g3_robustness_three_seeds": bool(g3)}


def main() -> int:
    pipeline = run_pipeline()
    gates = evaluate_gates(pipeline)
    verdict = "PASS" if (
        gates["g1_no_pure_strategy_dominance"]["no_defense_invadable"]
        and gates["g1_no_pure_strategy_dominance"]["full_defense_invadable"]
        and gates["g2_restart_determinism_byte_equal"]
        and gates["g3_robustness_three_seeds"]
    ) else "FAIL"

    trajectory_doc = {
        "schema": SCHEMA + ".trajectory", "version": "1.0.0",
        "rule": "evo4-t2-coevolution-v0",
        "derived_representation": True,
        "generations": GENERATIONS,
        "seed_main": MAIN_SEED,
        "robustness_seeds": ROBUSTNESS_SEEDS,
        "constants": {
            "defense_cost": DEFENSE_COST, "herbivory_gain": HERBIVORY_GAIN,
            "appetite": APPETITE, "pref_floor": PREF_FLOOR, "pref_eta": PREF_ETA,
            "mutation_rate": MUTATION_RATE, "defense_grid_step": 0.05,
        },
        "species": pipeline["species"],
        "trajectory": pipeline["main"]["trajectory"],
        "equilibrium": pipeline["main"]["equilibrium"],
        "trajectory_sha256": pipeline["digest_main"],
    }
    TRAJECTORY_PATH.write_text(json.dumps(trajectory_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    result = {
        "schema": SCHEMA + ".result", "version": "1.0.0",
        "rule": "evo4-t2-coevolution-v0",
        "source_manifest_sha256": pipeline["manifest_source_sha256"],
        "trajectory_artifact": "validation/ecology/evo4_t2_coevolution_trajectory.v1.json",
        "trajectory_sha256": pipeline["digest_main"],
        "replay_sha256": pipeline["digest_replay"],
        "gates": gates,
        "per_seed_gates": pipeline["per_seed_gates"],
        "verdict": verdict,
    }
    RESULT_PATH.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    final_mean = pipeline["main"]["trajectory"][-1]["mean_defense"]
    print(f"EVO4_T2_COEVOLUTION verdict={verdict} generations={GENERATIONS} "
          f"final_mean_defense={final_mean} traj_digest={pipeline['digest_main'][:16]}")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
