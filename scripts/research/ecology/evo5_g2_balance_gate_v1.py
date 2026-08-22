"""ECO.EVO6/G2 - balance gate: 200 ticks of generated rules over A0 terrain.
No phenotype class may go extinct or dominate; restart byte-equal; 3 seeds."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))
from evo5_rule_compiler_v1 import apply_rules, compile_rules  # noqa: E402
from evo5_rule_generator_v1 import generate_rules  # noqa: E402

TERRAIN = json.loads((ROOT / "validation/ecology/evo5_terrain_demo.v1.json").read_text(encoding="utf-8"))
TICKS = 200


def _phenotype(zone: str, feats: dict) -> dict:
    wet = zone == "riverside" or (zone == "ravine_bottom" and "water_dist_m" in feats)
    return {"root_type": "amphibious" if wet else "terrestrial",
            "form": "tall" if zone == "hill_slopes" else "low"}


def _run(seed: str):
    rules = compile_rules(generate_rules(seed))
    classes = {}
    for cell in TERRAIN["cells"]:
        ph = _phenotype(cell["zone"], cell["features"])
        ctx = {**cell["context"], "features": cell["features"]}
        ctx.setdefault("effective_conditions", {}).setdefault("wind_exposure",
            round(min(1.0, max(0.0, (float(cell["height"]) - 1.0) * 0.55)), 3))
        cls = f"{ph['root_type']}/{ph['form']}"
        vitality, death = 0.0, 0.0
        for _ in range(TICKS):
            eff = apply_rules(rules, ctx, ph)
            vitality += eff["vitality"]
            death += eff["death_chance"] * 10.0 * (1.0 + float(eff.get("seed_establishment", 0)))
        alive = vitality - death > -1.0
        classes.setdefault(cls, [0, 0])
        classes[cls][0] += 1
        classes[cls][1] += int(alive)
    return {k: round(v[1] / v[0], 3) for k, v in sorted(classes.items())}


def main() -> int:
    seeds = ["20260822", "20260823", "20260824"]
    run1 = _run(seeds[0])
    run2 = _run(seeds[0])
    robust = [_run(s) for s in seeds[1:]]
    gates = {
        "restart_byte_equal": run1 == run2,
        "no_class_extinct": all(v > 0.0 for v in run1.values()),
        "no_total_dominance": all(v < 0.98 for v in run1.values()),
        "robustness_3_seeds": all(all(v > 0.0 for v in r.values()) for r in robust),
    }
    ok = sum(1 for v in gates.values() if v)
    result = {"schema": "distributed_world_simulator.ecology.evo5_g2_balance.v1.result",
              "version": "1.0.0", "ticks": TICKS, "seeds": seeds, "gates": gates,
              "survival_rates": run1,
              "verdict": "PASS" if ok == len(gates) else "FAIL"}
    (ROOT / "validation/ecology/evo5_g2_balance_result.v1.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"EVO5_G2 verdict={result['verdict']} rules=12 classes={len(run1)} gates={ok}/{len(gates)}")
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
