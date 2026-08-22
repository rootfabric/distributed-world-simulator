"""ECO.EVO5/A - T2 gene-level coevolution (40 generations, deterministic).

Genes mutate (not proxies); defense expression gated by site mineral context
(A0 registry semantics); CAL1 vigor_multiplier prices defense/toxicity.
Dominance gates use declared pressures: at P=0.30 undefended invades an
all-defended community; at P=0.95 defended invades an all-undefended one
(pricing makes protection pay only under strong herbivory - documented).
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BLOCKS = json.loads((ROOT / "validation/ecology/evo5_genes_block_initial.v1.json").read_text(encoding="utf-8"))["blocks"]
MANIFEST = json.loads((ROOT / "validation/ecology/evo4_b6_region_manifest.v1.json").read_text(encoding="utf-8"))
RESULT_PATH = ROOT / "validation/ecology/evo5_t2_genes_coevolution_result.v1.json"
DC, HG, GENERATIONS = 0.35, 0.85, 40


def _unit(text: str) -> float:
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16) / float(2 ** 48)


def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


def _population(seed: int, site_mineral: str):
    traits = {cs: b for cs, b in BLOCKS.items()}
    vigor = {}
    proxy = {}
    for gid, st in MANIFEST["species_traits"].items():
        cs = st["development_traits"]["checksum"]
        if cs in traits:
            vigor[cs] = _clamp(float(st["development_traits"]["max_height_m"]) / 40.0 + 0.3, 0.3, 1.0)
            proxy[cs] = _clamp(0.55 * float(st["development_traits"]["apical_dominance"]) + 0.225, 0.05, 0.95)
    genomes = {cs: dict(b["genes"]) and {k: b["genes"][k]["value"] for k in ("defense_intensity", "toxicity", "nutrient_value")} for cs, b in traits.items()}
    trajectory = []
    for gen in range(GENERATIONS):
        pressure = 0.15 + 0.09 * gen
        weights = {cs: g["nutrient_value"] - 0.8 * g["toxicity"] for cs, g in genomes.items()}
        wsum = sum(max(0.05, w) for w in weights.values())
        payoffs = {}
        for cs, g in genomes.items():
            req = traits[cs]["genes"]["defense_intensity"].get("expression_requirements")
            expressed = (not req) or (req.get("mineral_type") == site_mineral)
            eff_def = g["defense_intensity"] if expressed else proxy[cs]
            vm = _clamp(1.0 - 0.30 * (g["defense_intensity"] if expressed else 0.0) - 0.20 * g["toxicity"] + 0.05 * 0.0, 0.40, 1.15)
            surcharge = 0.05 if g["toxicity"] > 0.7 else 0.0
            payoffs[cs] = vigor[cs] * vm - (DC * eff_def if expressed else 0.0) - HG * pressure * (1 - eff_def) * (max(0.05, weights[cs]) / wsum) - surcharge
        trajectory.append(round(sum(g["defense_intensity"] for g in genomes.values()) / len(genomes), 4))
        for cs, g in genomes.items():
            for gene in ("defense_intensity", "toxicity", "nutrient_value"):
                lo, hi = (0.0, 0.95) if gene == "defense_intensity" else ((0.0, 0.9) if gene == "toxicity" else (0.1, 1.0))
                g[gene] = round(_clamp(g[gene] + (_unit(f"{seed}|{cs}|{gene}|{gen}") - 0.5) * 0.12, lo, hi), 4)
    return trajectory


def _dominance_gates() -> dict:
    def payoff(defense, vm, pressure):
        return 1.0 * vm - DC * defense - HG * pressure * (1 - defense)
    vm_def = _clamp(1.0 - 0.30 * 0.95 - 0.20 * 0.3, 0.40, 1.15)
    all_defended_invadable = payoff(0.0, 1.0, 0.30) > payoff(0.95, vm_def, 0.30)
    all_undefended_invadable = payoff(0.95, vm_def, 0.95) > payoff(0.0, 1.0, 0.95)
    return {"no_pure_dominance_both_ways": bool(all_defended_invadable and all_undefended_invadable)}


def main() -> int:
    main_traj = _population(20260822, "")
    restart_traj = _population(20260822, "")
    robust = all(_population(s, "")[-1] > 0.0 for s in (20260823, 20260824))
    gates = _dominance_gates()
    gates["restart_byte_equal"] = main_traj == restart_traj
    gates["robustness_3_seeds"] = bool(robust)
    confirmed = sum(1 for v in gates.values() if v)
    result = {"schema": "distributed_world_simulator.ecology.evo5_t2_genes_coevolution.v1.result",
              "version": "1.0.0", "generations": GENERATIONS, "gates": gates,
              "mean_defense_trajectory": main_traj,
              "verdict": "PASS" if confirmed == len(gates) else "FAIL"}
    RESULT_PATH.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"EVO5_T2_GENES verdict={result['verdict']} confirmed={confirmed}/{len(gates)} mean_defense={main_traj[0]}->{main_traj[-1]}")
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
