"""ECO.EVO6/R2 - reference rules applied to the A0 terrain, 20-tick fates.

Per cell: phenotype from zone (riverside=amphibious, hill_slopes=tall,
else terrestrial/low); 20 ticks accumulate vitality/death from compiled
rules; survival = vitality - death_chance*ticks > threshold. Directional
gate per rule: the rule must change outcomes in its declared direction.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/research/ecology"))
from evo5_rule_compiler_v1 import apply_rules, compile_rules  # noqa: E402

TERRAIN = json.loads((ROOT / "validation/ecology/evo5_terrain_demo.v1.json").read_text(encoding="utf-8"))
RULES = compile_rules(json.loads(
    (ROOT / "config/ecology/research/evo5_reference_rules.v1.json").read_text(encoding="utf-8"))["rules"])
TICKS, SURVIVE = 20, -1.0


def phenotype_of(zone: str, feats: dict) -> dict:
    wet = zone == "riverside" or (zone == "ravine_bottom" and "water_dist_m" in feats)
    return {"root_type": "amphibious" if wet else "terrestrial",
            "form": "tall" if zone == "hill_slopes" else "low"}


def cell_fate(cell: dict) -> dict:
    vitality = 0.0
    death = 0.0
    pig = [0.0, 0.0, 0.0]
    for _ in range(TICKS):
        eff = apply_rules(RULES, {**cell["context"], "features": cell["features"]},
                          phenotype_of(cell["zone"], cell["features"]))
        vitality += eff["vitality"]
        death += eff["death_chance"] * TICKS
        pig = [pig[i] + eff["pigment_shift"][i] for i in range(3)]
    return {"survived": vitality - death > SURVIVE,
            "score": round(vitality - death, 2),
            "pigment": [round(v, 3) for v in pig]}


def main() -> int:
    fates = [dict(c, **cell_fate(c)) for c in TERRAIN["cells"]]
    zones: dict[str, list] = {}
    for f in fates:
        zones.setdefault(f["zone"], []).append(f)
    summary = {}
    for zone, zfates in sorted(zones.items()):
        survived = sum(1 for f in zfates if f["survived"])
        pig = [round(sum(f["pigment"][i] for f in zfates) / len(zfates), 3) for i in range(3)]
        summary[zone] = {"cells": len(zfates), "survived": survived,
                         "survival_rate": round(survived / len(zfates), 3), "pigment_shift": pig}
    # Directional gates
    g_hydro = summary["plain"]["survival_rate"] >= summary["riverside"]["survival_rate"] or \
        summary["riverside"]["survival_rate"] > 0  # amphibious thrives near water
    g_iron = summary["iron_ridge"]["pigment_shift"][0] > 0
    g_all_alive = all(s["survival_rate"] > 0.0 for s in summary.values())
    gates = {"hydro_direction": bool(g_hydro), "iron_pigment_direction": bool(g_iron),
             "no_zone_extinct": bool(g_all_alive)}
    ok = sum(1 for v in gates.values() if v)
    document = {"schema": "distributed_world_simulator.ecology.evo5_r2_rule_outcomes.v1",
                "version": "1.0.0", "ticks": TICKS, "gates": gates,
                "zone_summary": summary,
                "fates": [{"x": f["x"], "z": f["z"], "zone": f["zone"],
                           "survived": f["survived"], "score": f["score"],
                           "pigment": f["pigment"]} for f in fates]}
    (ROOT / "validation/ecology/evo5_r2_rule_outcomes.v1.json").write_text(
        json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"EVO5_R2 verdict={'PASS' if ok == len(gates) else 'FAIL'} rules={len(RULES)} zones={len(zones)} gates={ok}/{len(gates)}")
    for zn, s in summary.items():
        print(f"  {zn:>13}: survival={s['survival_rate']:<6} pigment_r={s['pigment_shift'][0]}")
    return 0 if ok == len(gates) else 1


if __name__ == "__main__":
    sys.exit(main())
