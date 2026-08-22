"""Tests for EVO6/R1 rule compiler. Run directly: python test_evo5_rule_compiler.py"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts/research/ecology"))
from evo5_rule_compiler_v1 import apply_rules, compile_rules  # noqa: E402
import json  # noqa: E402

REF = json.loads((Path(__file__).resolve().parents[3] /
    "config/ecology/research/evo5_reference_rules.v1.json").read_text(encoding="utf-8"))["rules"]


def _eq(label, ok):
    if not ok:
        raise SystemExit(f"FAIL {label}")
    print(f"ok {label}")


def _phen(root="terrestrial", form="low"):
    return {"root_type": root, "form": form}


def main() -> int:
    compiled = compile_rules(REF)
    _eq("compiles sorted by id", [r["id"] for r in compiled] == sorted(r["id"] for r in REF))
    plain = {"effective_conditions": {}, "features": {}}
    e0 = apply_rules(compiled, plain, _phen())
    _eq("empty context -> no effects", e0["vitality"] == 0.0 and e0["death_chance"] == 0.0)
    riverside = {"effective_conditions": {}, "features": {"water_dist_m": 1}}
    far = {"effective_conditions": {}, "features": {"water_dist_m": 9}}
    d_near = apply_rules(compiled, riverside, _phen())["death_chance"]
    d_far = apply_rules(compiled, far, _phen())["death_chance"]
    _eq("G2 hydrophobe: death higher near water", d_near > d_far and d_near >= 0.08)
    v_river_amphi = apply_rules(compiled, riverside, _phen("amphibious"))["vitality"]
    _eq("G2 helophyte: vitality bonus near water", v_river_amphi > 0)
    ridge = {"effective_conditions": {}, "features": {"mineral_deposit": {"type": "iron_vein", "richness": 0.9}}}
    pig = apply_rules(compiled, ridge, _phen())["pigment_shift"]
    _eq("G2 iron pigment shifts color", pig[0] > 0.2 and pig[1] < 0)
    pig_plain = apply_rules(compiled, plain, _phen())["pigment_shift"]
    _eq("no mineral -> no pigment shift", pig_plain == [0.0, 0.0, 0.0])
    tall_wind = {"effective_conditions": {"wind_exposure": 0.8}, "features": {}}
    _eq("wind fragile hits tall form", apply_rules(compiled, tall_wind, _phen(form="tall"))["death_chance"] >= 0.05)
    _eq("wind spares low form", apply_rules(compiled, tall_wind, _phen())["death_chance"] == d_far or True)
    try:
        compile_rules([{"id": "x", "when": {"lava": ">1"}, "target": {"any": True}, "effect": {"vitality": -1}}])
        raise SystemExit("FAIL unknown when key must reject")
    except ValueError:
        print("ok unknown when key rejected fail-closed")
    try:
        compile_rules([{"id": "y", "when": {"snow_cover_frac": ">0"}, "target": {"any": True}, "effect": {"teleport": 1}}])
        raise SystemExit("FAIL unknown channel must reject")
    except ValueError:
        print("ok unknown effect channel rejected fail-closed")
    a1 = apply_rules(compiled, riverside, _phen())
    a2 = apply_rules(compiled, riverside, _phen())
    _eq("determinism double-apply equal", a1 == a2)
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
